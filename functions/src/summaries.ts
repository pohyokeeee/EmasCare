import {DocumentData, Firestore, Query, Timestamp, Transaction} from "firebase-admin/firestore";
import {authorizeElder, loadActor, requireRole, requireTownship} from "./auth";
import {malaysiaDate} from "./checkins";
import {participationId} from "./completion_ids";
import {fail} from "./errors";
import {wireRecord} from "./scheduling";
import {documentId, envelope, inputObject} from "./validation";

export function progressPeriod(type: unknown, key: unknown, now: Timestamp) {
  if (type !== "week" && type !== "month") fail("invalid-argument", "INVALID_PERIOD");
  let date = malaysiaDate(now);
  if (type === "week") {
    const d = new Date(`${date}T00:00:00Z`); d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7)); date = d.toISOString().slice(0, 10);
  } else date = date.slice(0, 7);
  const periodKey = key == null ? date : key;
  if (typeof periodKey !== "string" || !(type === "week" ? /^\d{4}-\d\d-\d\d$/ : /^\d{4}-\d\d$/).test(periodKey) || periodKey.startsWith("0000")) fail("invalid-argument", "INVALID_PERIOD");
  const local = `${periodKey}${type === "month" ? "-01" : ""}`;
  const start = Date.parse(`${local}T00:00:00+08:00`);
  if (!Number.isFinite(start) || malaysiaDate(Timestamp.fromMillis(start)) !== local ||
      type === "week" && new Date(start + 8 * 3600000).getUTCDay() !== 1) fail("invalid-argument", "INVALID_PERIOD");
  const endDate = new Date(start + 8 * 3600000);
  if (type === "month") endDate.setUTCMonth(endDate.getUTCMonth() + 1); else endDate.setUTCDate(endDate.getUTCDate() + 7);
  return {periodKey, start, end: endDate.getTime() - 8 * 3600000};
}
async function bounded(tx: Transaction, query: Query) {
  const rows = await tx.get(query.limit(501));
  if (rows.size > 500) fail("resource-exhausted", "DEMO_LIMIT_EXCEEDED");
  return rows.docs;
}
export function sanitizeAvailability(input: DocumentData | undefined) {
  if (!input || input.isDemo !== true || !Array.isArray(input.cells) || input.cells.length > 28) fail("failed-precondition", "SUMMARY_NOT_CONFIGURED");
  const seen = new Set<string>(), members = new Set<string>();
  const cells = input.cells.map((c: DocumentData) => {
    if (!["retiree", "student", "working_adult"].includes(c.cohort) || !Number.isInteger(c.weekday) || c.weekday < 1 || c.weekday > 7 ||
        !Number.isInteger(c.startMinute) || !Number.isInteger(c.endMinute) || c.startMinute < 0 || c.endMinute > 1440 || c.startMinute >= c.endMinute ||
        !Array.isArray(c.helperIds) || !Array.isArray(c.requestIds) || [...c.helperIds, ...c.requestIds].some((id) => typeof id !== "string")) fail("failed-precondition", "INVALID_SUMMARY_INPUT");
    const key = `${c.weekday}_${c.startMinute}_${c.endMinute}_${c.cohort}`;
    // Fixed disjoint cohorts prevent differencing overlapping small cells.
    if (seen.has(key)) fail("failed-precondition", "INVALID_SUMMARY_INPUT"); seen.add(key);
    const ids = [...new Set<string>(c.helperIds)];
    for (const id of ids) { if (members.has(id)) fail("failed-precondition", "INVALID_SUMMARY_INPUT"); members.add(id); }
    const suppressed = ids.length < 5;
    return {weekday: c.weekday, startMinute: c.startMinute, endMinute: c.endMinute, cohort: c.cohort,
      helperCount: suppressed ? null : ids.length, requestCount: suppressed ? null : new Set(c.requestIds).size, suppressed};
  });
  return {townshipId: input.townshipId, cells, isDemo: true, updatedAt: input.updatedAt};
}

export function createSummaryService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function getProgress(uid: string, value: unknown) {
    const input = inputObject(value, ["scope", "entityId", "periodType", "periodKey"]), entityId = documentId(input.entityId);
    if (!["elder", "helper", "household", "township"].includes(input.scope as string)) fail("invalid-argument", "INVALID_PROGRESS_SCOPE");
    const now = clock(), period = progressPeriod(input.periodType, input.periodKey, now);
    return db.runTransaction(async (tx) => {
      const actor = await loadActor(db, uid, tx), scope = input.scope as string;
      let townshipId = actor.townshipId;
      const householdMembers = new Set<string>();
      if (scope === "elder") await authorizeElder(db, tx, actor, entityId, "daily_sharing");
      if (scope === "helper") {
        const helper = await loadActor(db, entityId, tx); requireTownship(actor, helper.townshipId);
        if (helper.role !== "helper" || !(actor.role === "coordinator" || actor.role === "helper" && uid === entityId)) fail("permission-denied", "PROGRESS_ACCESS_DENIED");
      }
      if (scope === "household") {
        const household = (await tx.get(db.doc(`households/${entityId}`))).data();
        if (!household) fail("not-found", "HOUSEHOLD_NOT_FOUND"); requireTownship(actor, household.townshipId);
        if (actor.role !== "coordinator" && (actor.householdId !== entityId || !household.memberUids?.includes(uid))) fail("permission-denied", "UNRELATED_HOUSEHOLD");
        for (const member of household.memberUids ?? []) householdMembers.add(member);
      }
      if (scope === "township") { requireTownship(actor, entityId); townshipId = entityId; }
      const profiles = await bounded(tx, db.collection("users").where("townshipId", "==", townshipId));
      if (scope === "township" && actor.role !== "coordinator" && profiles.filter((p) => p.data().role === "elder").length < 5) fail("failed-precondition", "SUMMARY_SUPPRESSED");
      const counts = {outings: 0, helpingSessions: 0, weekendGiveBack: 0};
      let pendingOutingClassifications = 0, latestOuting: DocumentData | null = null;
      const within = (at: unknown): at is Timestamp => at instanceof Timestamp && at.toMillis() >= period.start && at.toMillis() < period.end;
      if (scope === "elder" || scope === "township") {
        let query: Query = db.collection("participations").where("townshipId", "==", townshipId);
        if (scope === "elder") query = query.where("beneficiaryUid", "==", entityId);
        const participations = await bounded(tx, query);
        for (const p of participations) {
          const data = p.data();
          if (data.beneficiaryRole !== "elder" || !within(data.verifiedAt) || p.id !== participationId(data.completionEventId, data.beneficiaryUid)) continue;
          const marker = (await tx.get(db.doc(`completionMarkers/${p.id}`))).data();
          if (marker?.participationId !== p.id) continue;
          if (data.outingClassification === "pending_definition") pendingOutingClassifications++;
          if (data.outingClassification !== "counts") continue;
          counts.outings++;
          if (scope === "elder" && (!latestOuting || data.verifiedAt.toMillis() > Date.parse(latestOuting.completedAt))) {
            const activity = data.activityId ? (await tx.get(db.doc(`activities/${data.activityId}`))).data() : null;
            latestOuting = {participationId: p.id, requestId: data.sourceRequestIds?.[0] ?? null, attendanceId: data.attendanceId ?? null,
              activityTitle: activity?.title ?? {bm: "Berjalan bersama", en: "Companion walk"}, completedAt: data.verifiedAt.toDate().toISOString()};
          }
        }
      }
      if (scope === "helper" || scope === "household") {
        const helpers = scope === "helper" ? [entityId] : profiles.filter((p) => p.data().role === "helper" && p.data().householdId === entityId && householdMembers.has(p.id)).map((p) => p.id);
        for (const helperId of helpers) {
          const requests = await bounded(tx, db.collection("requests").where("townshipId", "==", townshipId).where("helperId", "==", helperId));
          for (const r of requests) {
            const data = r.data();
            if (data.state !== "completed" || data.elderConfirmation?.uid !== data.elderId || data.helperConfirmation?.uid !== helperId || !within(data.completedAt)) continue;
            if (scope === "helper") counts.helpingSessions++;
            // Reporting period uses final confirmation; weekend classification uses the actual scheduled session day.
            if (data.startsAt instanceof Timestamp && [0, 6].includes(new Date(data.startsAt.toMillis() + 8 * 3600000).getUTCDay())) counts.weekendGiveBack++;
          }
        }
      }
      const config = (await tx.get(db.doc(`progressTargets/${townshipId}`))).data();
      const target = config?.[scope]?.[input.periodType as string] ?? {};
      const goal = (v: unknown): number | null => Number.isSafeInteger(v) && (v as number) > 0 ? v as number : null;
      const targets = {outings: scope === "elder" && input.periodType === "week" ? 2 : goal(target.outings),
        helpingSessions: goal(target.helpingSessions), weekendGiveBack: goal(target.weekendGiveBack)};
      // Separate illustrative history never enters completion, rewards or financial records.
      const history = scope === "household" || scope === "township" ? (await tx.get(db.doc(`demoProgressHistory/${scope}_${entityId}`))).data() : null;
      let includesSeededHistory = false;
      if (history?.isDemo === true && history.townshipId === townshipId && Array.isArray(history.entries)) for (const row of history.entries) {
        if (within(row.at) && Number.isSafeInteger(row.count) && row.count > 0 && (scope === "township" && row.metric === "outings" || scope === "household" && row.metric === "weekendGiveBack")) {
          counts[row.metric as "outings" | "weekendGiveBack"] += row.count; includesSeededHistory = true;
        }
      }
      return envelope({progress: {id: `${scope}_${entityId}_${input.periodType}_${period.periodKey}`, scope, entityId, periodType: input.periodType,
        periodKey: period.periodKey, counts, targets, pendingOutingClassifications, latestOuting, isDemo: true, includesSeededHistory, updatedAt: now.toDate().toISOString()}});
    });
  }
  async function getAvailabilitySummary(uid: string, value: unknown) {
    inputObject(value, []);
    return db.runTransaction(async (tx) => {
      const actor = await loadActor(db, uid, tx), raw = (await tx.get(db.doc(`availabilityDemoInputs/${actor.townshipId}`))).data();
      if (raw?.townshipId !== actor.townshipId) fail("failed-precondition", "SUMMARY_NOT_CONFIGURED");
      return envelope({availabilitySummary: wireRecord(actor.townshipId, sanitizeAvailability(raw))});
    });
  }
  async function getCoordinatorSummary(uid: string, value: unknown) {
    inputObject(value, []);
    return db.runTransaction(async (tx) => {
      const actor = await loadActor(db, uid, tx); requireRole(actor, ["coordinator"]);
      const now = clock(), localDate = malaysiaDate(now), countStates = (rows: DocumentData[], field: string, states: string[]) =>
        Object.fromEntries(states.map((state) => [state, rows.filter((d) => d[field] === state).length]));
      const records = async (name: string) => (await bounded(tx, db.collection(name).where("townshipId", "==", actor.townshipId))).map((d) => d.data());
      const checkins = (await records("checkins")).filter((c) => c.localDate === localDate), places = await records("places");
      const profiles = await records("users");
      const summary = {townshipId: actor.townshipId, localDate,
        checkins: {...countStates(checkins, "state", ["pending", "reminded", "missed", "ok", "paused"]),
          notMaterialized: Math.max(0, profiles.filter((p) => p.role === "elder").length - checkins.length)},
        requests: countStates(await records("requests"), "state", ["requested", "assigned", "accepted", "in_progress", "awaiting_confirmation", "completed", "cancelled"]),
        attendance: countStates(await records("activityAttendances"), "status", ["submitted", "verified", "rejected"]),
        reports: countStates(await records("reports"), "state", ["new", "seen", "done"]),
        placeWarnings: {active: places.filter((p) => p.liveStatus?.expiresAt instanceof Timestamp && p.liveStatus.expiresAt.toMillis() > now.toMillis()).length,
          needsReview: places.filter((p) => p.liveStatus && (!(p.liveStatus.expiresAt instanceof Timestamp) || p.liveStatus.expiresAt.toMillis() <= now.toMillis())).length},
        isDemo: true, updatedAt: now.toDate().toISOString()};
      return envelope({summary});
    });
  }
  return {getProgress, getAvailabilitySummary, getCoordinatorSummary};
}
