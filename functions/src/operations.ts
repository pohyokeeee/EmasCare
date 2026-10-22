import {DocumentData, Firestore, Timestamp} from "firebase-admin/firestore";
import {authorizeElder, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand, tupleId} from "./commands";
import {helperBlockId, requestAccess} from "./sessions";
import {participationId} from "./completion_ids";
import {fail} from "./errors";
import {prepareNotices} from "./notifications";
import {wireRecord} from "./scheduling";
import {documentId, envelope, inputObject, stringField} from "./validation";

export function instant(value: unknown, reason = "INVALID_TIME_RANGE") {
  if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value) || value.startsWith("0000-")) fail("invalid-argument", reason);
  const ms = Date.parse(value), normalized = value.includes(".") ? value : value.replace(/Z$/, ".000Z");
  if (!Number.isFinite(ms) || new Date(ms).toISOString() !== normalized) fail("invalid-argument", reason);
  return Timestamp.fromMillis(ms);
}

export function createOperationsService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function setPlaceWarning(uid: string, value: unknown) {
    const input = inputObject(value, ["placeId", "warning"], true), id = documentId(input.placeId);
    let warning: {level: string; text: string; expiresAt: Timestamp} | null = null;
    if (input.warning !== null) {
      const w = input.warning as Record<string, unknown>;
      if (!w || typeof w !== "object" || Array.isArray(w) || Object.keys(w).some((k) => !["level", "text", "expiresAt"].includes(k)) ||
          !["warning", "closed"].includes(w.level as string)) fail("invalid-argument", "INVALID_WARNING");
      warning = {level: w.level as string, text: stringField(w.text, "INVALID_WARNING", 300).trim(), expiresAt: instant(w.expiresAt)};
    }
    return runCommand({db, uid, name: "setPlaceWarning", key: input.idempotencyKey as string,
      payload: {placeId: id, warning: warning ? {...warning, expiresAt: warning.expiresAt.toDate().toISOString()} : null},
      authorize: async (tx, actor) => {
        requireRole(actor, ["coordinator"]); const place = (await tx.get(db.doc(`places/${id}`))).data();
        if (!place) fail("not-found", "PLACE_NOT_FOUND"); requireTownship(actor, place.townshipId); return place;
      }, execute: async (tx, actor, place) => {
        const now = clock();
        if (warning && warning.expiresAt.toMillis() <= now.toMillis()) fail("invalid-argument", "INVALID_WARNING_EXPIRY");
        const next = {...place, liveStatus: warning ? {...warning, updatedAt: now, setBy: actor.uid} : null, updatedAt: now};
        tx.set(db.doc(`places/${id}`), next); return envelope({place: wireRecord(id, next)});
      }});
  }
  async function submitReport(uid: string, value: unknown) {
    const input = inputObject(value, ["kind", "text", "placeId", "requestId", "helperId"], true);
    if (!["place_problem", "helper_report"].includes(input.kind as string)) fail("invalid-argument", "UNSUPPORTED_REPORT_KIND");
    const text = stringField(input.text, "INVALID_REPORT_TEXT", 1000).trim();
    const optional = (v: unknown) => v === undefined || v === null ? null : documentId(v);
    const placeId = optional(input.placeId), requestId = optional(input.requestId), helperId = optional(input.helperId);
    if (input.kind === "place_problem" ? !placeId || helperId !== null : !requestId || !helperId || placeId !== null) fail("invalid-argument", "INVALID_REPORT_LINK");
    const id = tupleId("report", uid, input.idempotencyKey as string);
    return runCommand({db, uid, name: "submitReport", key: input.idempotencyKey as string,
      payload: {kind: input.kind, text, placeId, requestId, helperId}, authorize: async (tx, actor) => {
        if (placeId) {
          const place = (await tx.get(db.doc(`places/${placeId}`))).data();
          if (!place) fail("not-found", "PLACE_NOT_FOUND"); requireTownship(actor, place.townshipId);
        }
        const request = requestId ? await requestAccess(db, tx, actor, requestId) : null;
        if (placeId && request && request.placeId !== placeId) fail("invalid-argument", "INVALID_REPORT_LINK");
        if (helperId && request?.helperId !== helperId) fail("permission-denied", "NOT_ASSIGNED_HELPER");
        return request;
      }, execute: async (tx, actor, request) => {
        const now = clock(), report = {townshipId: actor.townshipId, createdBy: actor.uid, kind: input.kind, placeId, requestId, helperId,
          elderId: request?.elderId ?? null, householdId: request?.householdId ?? null, text, state: "new", reviewedBy: null, reviewedAt: null, createdAt: now, updatedAt: now};
        tx.create(db.doc(`reports/${id}`), report); return envelope({report: wireRecord(id, report)});
      }});
  }
  async function reviewReport(uid: string, value: unknown) {
    const input = inputObject(value, ["reportId", "state"], true), id = documentId(input.reportId);
    if (!["seen", "done"].includes(input.state as string)) fail("invalid-argument", "INVALID_REPORT_STATE");
    return runCommand({db, uid, name: "reviewReport", key: input.idempotencyKey as string, payload: {reportId: id, state: input.state},
      authorize: async (tx, actor) => {
        requireRole(actor, ["coordinator"]); const report = (await tx.get(db.doc(`reports/${id}`))).data();
        if (!report) fail("not-found", "REPORT_NOT_FOUND"); requireTownship(actor, report.townshipId); return report;
      }, execute: async (tx, actor, report) => {
        if (report.state === input.state) return envelope({report: wireRecord(id, report)});
        if (report.state === "done") fail("failed-precondition", "INVALID_TRANSITION");
        const now = clock(), next = {...report, state: input.state, reviewedBy: actor.uid, reviewedAt: now, updatedAt: now};
        tx.set(db.doc(`reports/${id}`), next); return envelope({report: wireRecord(id, next)});
      }});
  }
  async function blockHelper(uid: string, value: unknown) {
    const input = inputObject(value, ["elderId", "helperId", "reason"], true), elderId = documentId(input.elderId), helperId = documentId(input.helperId);
    const reason = stringField(input.reason, "INVALID_BLOCK_REASON", 500).trim(), id = helperBlockId(elderId, helperId);
    return runCommand({db, uid, name: "blockHelper", key: input.idempotencyKey as string, payload: {elderId, helperId, reason},
      authorize: async (tx, actor) => {
        requireRole(actor, ["elder", "coordinator"]); await authorizeElder(db, tx, actor, elderId, "family_booking");
        const helper = await loadActor(db, helperId, tx); requireTownship(actor, helper.townshipId);
        if (helper.role !== "helper") fail("failed-precondition", "HELPER_REQUIRED");
        if (actor.role !== "coordinator") {
          const pair = await tx.get(db.collection("pairings").where("elderId", "==", elderId).where("helperId", "==", helperId).where("townshipId", "==", actor.townshipId).limit(1));
          const request = await tx.get(db.collection("requests").where("elderId", "==", elderId).where("helperId", "==", helperId).where("townshipId", "==", actor.townshipId).limit(1));
          if (pair.empty && request.empty) fail("permission-denied", "HELPER_RELATION_REQUIRED");
        }
      }, execute: async (tx, actor) => {
        const ref = db.doc(`helperBlocks/${id}`), before = await tx.get(ref), now = clock();
        if (!before.exists) tx.create(ref, {elderId, helperId, townshipId: actor.townshipId, reason, createdBy: actor.uid, createdAt: now, updatedAt: now});
        return envelope({elderId, helperId, blocked: true});
      }});
  }
  async function sendFamilyCheer(uid: string, value: unknown) {
    const input = inputObject(value, ["participationId"], true), pid = documentId(input.participationId), id = tupleId("family-cheer", uid, pid);
    return runCommand({db, uid, name: "sendFamilyCheer", key: input.idempotencyKey as string, payload: {participationId: pid},
      authorize: async (tx, actor) => {
        requireRole(actor, ["family"]); const p = (await tx.get(db.doc(`participations/${pid}`))).data();
        const marker = (await tx.get(db.doc(`completionMarkers/${pid}`))).data();
        if (!p || p.beneficiaryRole !== "elder" || p.outingClassification !== "counts" || !(p.verifiedAt instanceof Timestamp) ||
            pid !== participationId(p.completionEventId, p.beneficiaryUid) || marker?.participationId !== pid) fail("failed-precondition", "VERIFIED_OUTING_REQUIRED");
        await authorizeElder(db, tx, actor, p.beneficiaryUid, "daily_sharing"); requireTownship(actor, p.townshipId); return p;
      }, execute: async (tx, actor, p: DocumentData) => {
        const ref = db.doc(`cheers/${id}`), before = (await tx.get(ref)).data(), now = clock();
        const notice = await prepareNotices(db, tx, [{recipientUid: p.beneficiaryUid, elderId: p.beneficiaryUid, kind: "family_cheer",
          entityId: pid, consentScope: "none", messageParams: {kind: "clap"}}], id, now);
        const cheer = before ?? {familyUid: actor.uid, elderId: p.beneficiaryUid, participationId: pid, kind: "clap", createdAt: now};
        if (!before) tx.create(ref, cheer); notice.write(); return envelope({cheer: wireRecord(id, cheer)});
      }});
  }
  return {setPlaceWarning, submitReport, reviewReport, blockHelper, sendFamilyCheer};
}
