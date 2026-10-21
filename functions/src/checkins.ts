import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {Actor, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject} from "./validation";

const offsetMs = 8 * 60 * 60 * 1000;
const timePattern = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export type CheckInState = "pending" | "reminded" | "missed" | "ok" | "paused";
interface Settings extends DocumentData {
  familySharingEnabled: boolean;
  familyBookingEnabled: boolean;
  dueLocalTime: string;
  graceMinutes: number;
  pausedOn: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
interface CheckIn extends DocumentData {
  elderId: string;
  townshipId: string;
  localDate: string;
  state: CheckInState;
  dueAt: Timestamp;
  graceEndsAt: Timestamp;
  submittedAt: Timestamp | null;
  recordedBy: string | null;
  source: "app" | "coordinator_phone" | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
interface ElderAccess {
  elder: Actor;
  householdId: string;
  household: DocumentData;
}

// Malaysia uses UTC+08:00 without DST. Compute dates on the server, including
// rollover across UTC date/month/year boundaries; callers cannot choose a day.
export function malaysiaDate(now: Timestamp): string {
  return new Date(now.toMillis() + offsetMs).toISOString().slice(0, 10);
}

export function dailySchedule(now: Timestamp, dueLocalTime: string, graceMinutes: number) {
  const localDate = malaysiaDate(now);
  const dueAt = Timestamp.fromMillis(Date.parse(`${localDate}T${dueLocalTime}:00+08:00`));
  return {localDate, dueAt, graceEndsAt: Timestamp.fromMillis(dueAt.toMillis() + graceMinutes * 60000)};
}

export function unsubmittedState(now: Timestamp, settings: Pick<Settings, "dueLocalTime" | "graceMinutes" | "pausedOn">): CheckInState {
  const schedule = dailySchedule(now, settings.dueLocalTime, settings.graceMinutes);
  if (settings.pausedOn === schedule.localDate) return "paused";
  if (now.toMillis() < schedule.dueAt.toMillis()) return "pending";
  if (now.toMillis() < schedule.graceEndsAt.toMillis()) return "reminded";
  return "missed";
}

function parseSettings(input: Record<string, unknown>) {
  if (typeof input.familySharingEnabled !== "boolean" || typeof input.familyBookingEnabled !== "boolean" ||
      typeof input.pauseToday !== "boolean") fail("invalid-argument", "INVALID_SETTINGS");
  if (typeof input.dueLocalTime !== "string" || !timePattern.test(input.dueLocalTime)) {
    fail("invalid-argument", "INVALID_DUE_TIME");
  }
  if (typeof input.graceMinutes !== "number" || !Number.isInteger(input.graceMinutes) ||
      input.graceMinutes < 0 || input.graceMinutes > 1440) fail("invalid-argument", "INVALID_GRACE_MINUTES");
  return {familySharingEnabled: input.familySharingEnabled, familyBookingEnabled: input.familyBookingEnabled,
    dueLocalTime: input.dueLocalTime, graceMinutes: input.graceMinutes, pauseToday: input.pauseToday};
}

async function elderAccess(db: Firestore, tx: Transaction, actor: Actor, elderId: string): Promise<ElderAccess> {
  const elder = actor.uid === elderId ? actor : await loadActor(db, elderId, tx);
  if (elder.role !== "elder") fail("failed-precondition", "ELDER_REQUIRED");
  requireTownship(actor, elder.townshipId);
  if (!elder.householdId) fail("failed-precondition", "ELDER_HOUSEHOLD_REQUIRED");
  const household = (await tx.get(db.doc(`households/${elder.householdId}`))).data();
  if (!household || household.townshipId !== elder.townshipId ||
      !Array.isArray(household.memberUids) || !household.memberUids.includes(elderId) ||
      !Array.isArray(household.elderIds) || !household.elderIds.includes(elderId)) {
    fail("permission-denied", "UNRELATED_HOUSEHOLD");
  }
  return {elder, householdId: elder.householdId, household};
}

function wire(id: string, data: DocumentData) {
  return {id, ...Object.fromEntries(Object.entries(data).map(([key, value]) =>
    [key, value instanceof Timestamp ? value.toDate().toISOString() : value]))};
}

function readSettings(data: DocumentData | undefined): Settings {
  if (!data || typeof data.familySharingEnabled !== "boolean" || typeof data.familyBookingEnabled !== "boolean" ||
      typeof data.dueLocalTime !== "string" || !timePattern.test(data.dueLocalTime) ||
      !Number.isInteger(data.graceMinutes) || data.graceMinutes < 0 || data.graceMinutes > 1440 ||
      !(data.pausedOn === null || typeof data.pausedOn === "string")) {
    fail("failed-precondition", "SETTINGS_NOT_CONFIGURED");
  }
  return data as Settings;
}

function makeCheckIn(access: ElderAccess, settings: Settings, now: Timestamp, before?: CheckIn): CheckIn {
  if (before?.state === "ok") return before;
  const schedule = dailySchedule(now, settings.dueLocalTime, settings.graceMinutes);
  return {elderId: access.elder.uid, townshipId: access.elder.townshipId, ...schedule,
    state: unsubmittedState(now, settings), submittedAt: null, recordedBy: null, source: null,
    createdAt: before?.createdAt ?? now, updatedAt: now};
}

function dailyStatus(access: ElderAccess, checkin: CheckIn) {
  // Whitelist the family-safe projection. Never copy the private source record,
  // coordinator identity, schedule settings, arbitrary notes or wallet data.
  return {elderId: access.elder.uid, householdId: access.householdId, localDate: checkin.localDate,
    state: checkin.state, submittedAt: checkin.submittedAt, updatedAt: checkin.updatedAt};
}

// The clock is injected only into internal service tests. No callable accepts
// a timestamp, local date, actor/source identity or test-clock field.
export function createCheckInService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function saveElderSettings(uid: string, value: unknown) {
    const input = inputObject(value, ["familySharingEnabled", "familyBookingEnabled", "dueLocalTime", "graceMinutes", "pauseToday"], true);
    const parsed = parseSettings(input);
    return runCommand({db, uid, name: "saveElderSettings", key: input.idempotencyKey as string, payload: parsed,
      authorize: async (tx, actor) => {
        requireRole(actor, ["elder"]);
        return elderAccess(db, tx, actor, actor.uid);
      },
      execute: async (tx, actor, access) => {
        const now = clock();
        const date = malaysiaDate(now);
        const id = `${actor.uid}_${date}`;
        const settingsRef = db.doc(`elderSettings/${actor.uid}`);
        const checkinRef = db.doc(`checkins/${id}`);
        const [oldSettings, oldCheckin] = await tx.getAll(settingsRef, checkinRef);
        const {pauseToday, ...business} = parsed;
        const settings: Settings = {...business, pausedOn: pauseToday ? date : null,
          createdAt: oldSettings!.data()?.createdAt ?? now, updatedAt: now};
        const checkin = makeCheckIn(access, settings, now, oldCheckin!.data() as CheckIn | undefined);
        tx.set(settingsRef, settings);
        tx.update(db.doc(`households/${access.householdId}`), {
          elderAccess: {...access.household.elderAccess, [actor.uid]: {displayName: actor.displayName,
            familySharingEnabled: settings.familySharingEnabled, familyBookingEnabled: settings.familyBookingEnabled}},
          updatedAt: now,
        });
        tx.set(checkinRef, checkin);
        tx.set(db.doc(`dailyStatuses/${id}`), dailyStatus(access, checkin));
        return envelope({settings: wire(actor.uid, settings)});
      },
    });
  }

  async function submit(uid: string, value: unknown, phone: boolean) {
    const input = inputObject(value, phone ? ["elderId"] : [], true);
    const target = phone ? documentId(input.elderId) : uid;
    return runCommand({db, uid, name: phone ? "recordPhoneResponse" : "submitCheckIn",
      key: input.idempotencyKey as string, payload: phone ? {elderId: target} : {},
      authorize: async (tx, actor) => {
        requireRole(actor, phone ? ["coordinator"] : ["elder"]);
        return elderAccess(db, tx, actor, target);
      },
      execute: async (tx, actor, access) => {
        const now = clock();
        const id = `${target}_${malaysiaDate(now)}`;
        const settingsRef = db.doc(`elderSettings/${target}`);
        const checkinRef = db.doc(`checkins/${id}`);
        const [settingsSnapshot, existing] = await tx.getAll(settingsRef, checkinRef);
        const settings = readSettings(settingsSnapshot!.data());
        const before = existing!.data() as CheckIn | undefined;
        let checkin = before;
        if (before?.state !== "ok") {
          if (settings.pausedOn === malaysiaDate(now)) fail("failed-precondition", "CHECKIN_PAUSED");
          checkin = {...makeCheckIn(access, settings, now, before), state: "ok", submittedAt: now,
            recordedBy: actor.uid, source: phone ? "coordinator_phone" : "app", updatedAt: now};
          tx.set(checkinRef, checkin);
        }
        const status = dailyStatus(access, checkin!);
        tx.set(db.doc(`dailyStatuses/${id}`), status);
        return envelope({checkin: wire(id, checkin!), dailyStatus: wire(id, status)});
      },
    });
  }

  return {saveElderSettings, submitCheckIn: (uid: string, input: unknown) => submit(uid, input, false),
    recordPhoneResponse: (uid: string, input: unknown) => submit(uid, input, true)};
}
