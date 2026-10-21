import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {Actor, loadActor, requireRole, requireTownship} from "./auth";
import {runCommand} from "./commands";
import {activityLockId, attendanceId, completeActivityAttendance, completionId, participationId} from "./completions";
import {fail} from "./errors";
import {wireRecord} from "./scheduling";
import {documentId, envelope, inputObject, stringField} from "./validation";

async function elderScope(db: Firestore, tx: Transaction, actor: Actor, elder: Actor, householdId: string | null) {
  if (elder.role !== "elder") fail("permission-denied", "ELDER_ACCESS_DENIED");
  requireTownship(actor, elder.townshipId);
  if (!elder.householdId) fail("failed-precondition", "ELDER_HOUSEHOLD_REQUIRED");
  const household = (await tx.get(db.doc(`households/${elder.householdId}`))).data();
  if (householdId !== elder.householdId || !household || household.townshipId !== elder.townshipId ||
      !household.memberUids?.includes(elder.uid) || !household.elderIds?.includes(elder.uid)) fail("permission-denied", "UNRELATED_HOUSEHOLD");
}

async function activityScope(db: Firestore, tx: Transaction, actor: Actor, id: string) {
  const activity = (await tx.get(db.doc(`activities/${id}`))).data();
  if (!activity) fail("not-found", "ACTIVITY_NOT_FOUND");
  requireTownship(actor, activity.townshipId);
  return activity;
}

function finishedActivity(activity: DocumentData, now: Timestamp) {
  if (activity.participationMode !== "in_person") fail("failed-precondition", "ACTIVITY_NOT_IN_PERSON");
  if (!(activity.startsAt instanceof Timestamp) || !(activity.endsAt instanceof Timestamp) ||
      activity.endsAt.toMillis() <= activity.startsAt.toMillis()) fail("failed-precondition", "INVALID_ACTIVITY_SCHEDULE");
  if (now.toMillis() < activity.endsAt.toMillis()) fail("failed-precondition", "ACTIVITY_NOT_FINISHED");
}

// A live or partially confirmed companion session can never be verified by a
// coordinator instead. Read its source in the same lock/attendance transaction.
async function sessionSource(db: Firestore, tx: Transaction, activityId: string, elderId: string,
  lock: DocumentData | undefined, attendance: DocumentData | undefined) {
  if (lock?.requestId && attendance?.linkedRequestId && lock.requestId !== attendance.linkedRequestId) {
    fail("failed-precondition", "ATTENDANCE_MANAGED_BY_SESSION");
  }
  const id = lock?.requestId ?? attendance?.linkedRequestId;
  if (!id) {
    if (attendance?.mode === "companion_session") fail("failed-precondition", "ATTENDANCE_MANAGED_BY_SESSION");
    return false;
  }
  const request = (await tx.get(db.doc(`requests/${id}`))).data();
  if (!request || request.activityId !== activityId || request.elderId !== elderId) fail("failed-precondition", "ATTENDANCE_MANAGED_BY_SESSION");
  if (request.state === "cancelled" && attendance?.mode !== "companion_session") return false;
  const eventId = completionId(activityId, id);
  if (request.state !== "completed" || request.elderConfirmation?.uid !== elderId ||
      request.helperConfirmation?.uid !== request.helperId || !request.helperId ||
      request.completionEventId !== eventId || attendance?.status !== "verified" ||
      attendance.completionEventId !== eventId || attendance.participationId !== participationId(eventId, elderId)) {
    fail("failed-precondition", "ATTENDANCE_MANAGED_BY_SESSION");
  }
  return true;
}

export function createAttendanceService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function submitActivityAttendance(uid: string, value: unknown) {
    const input = inputObject(value, ["activityId"], true), activityId = documentId(input.activityId);
    const id = attendanceId(activityId, uid);
    return runCommand({db, uid, name: "submitActivityAttendance", key: input.idempotencyKey as string, payload: {activityId},
      authorize: async (tx, actor) => {
        requireRole(actor, ["elder"]);
        await elderScope(db, tx, actor, actor, actor.householdId);
        const activity = await activityScope(db, tx, actor, activityId);
        const before = (await tx.get(db.doc(`activityAttendances/${id}`))).data();
        if (before && (before.elderId !== actor.uid || before.activityId !== activityId || before.townshipId !== actor.townshipId ||
            before.householdId !== actor.householdId)) fail("permission-denied", "ATTENDANCE_ACCESS_DENIED");
        return {activity, before};
      }, execute: async (tx, actor, {activity, before}) => {
        const now = clock(); finishedActivity(activity, now);
        const lockRef = db.doc(`activityElderLocks/${activityLockId(activityId, actor.uid)}`);
        const lock = (await tx.get(lockRef)).data();
        await sessionSource(db, tx, activityId, actor.uid, lock, before);
        if (before) return envelope({attendance: wireRecord(id, before)});
        if (lock?.state === "completed") fail("failed-precondition", "ACTIVITY_ALREADY_COMPLETED");
        const attendance = {townshipId: actor.townshipId, householdId: actor.householdId, activityId, elderId: actor.uid,
          mode: "standalone", status: "submitted", linkedRequestId: null, submittedAt: now, verifiedAt: null,
          verificationMethod: null, reviewedBy: null, reviewedAt: null, reviewNote: null,
          completionEventId: null, participationId: null, createdAt: now, updatedAt: now};
        tx.create(db.doc(`activityAttendances/${id}`), attendance);
        tx.set(lockRef, {activityId, elderId: actor.uid, townshipId: actor.townshipId, requestId: null,
          attendanceId: id, state: "attendance_submitted", updatedAt: now});
        return envelope({attendance: wireRecord(id, attendance)});
      }});
  }

  async function reviewActivityAttendance(uid: string, value: unknown) {
    const input = inputObject(value, ["attendanceId", "decision", "verificationMethod", "note"], true);
    const id = documentId(input.attendanceId), decision = input.decision;
    if (decision !== "verify" && decision !== "reject") fail("invalid-argument", "INVALID_REVIEW_DECISION");
    if (decision === "verify" ? !["coordinator_observed", "organizer_roster"].includes(input.verificationMethod as string) : input.verificationMethod !== null) {
      fail("invalid-argument", "INVALID_VERIFICATION_METHOD");
    }
    const note = stringField(input.note, "INVALID_REVIEW_NOTE", 500).trim();
    return runCommand({db, uid, name: "reviewActivityAttendance", key: input.idempotencyKey as string,
      payload: {attendanceId: id, decision, verificationMethod: input.verificationMethod, note},
      authorize: async (tx, actor) => {
        requireRole(actor, ["coordinator"]);
        const before = (await tx.get(db.doc(`activityAttendances/${id}`))).data();
        if (!before) fail("not-found", "ATTENDANCE_NOT_FOUND");
        requireTownship(actor, before.townshipId);
        if (id !== attendanceId(documentId(before.activityId), documentId(before.elderId))) fail("failed-precondition", "INVALID_ATTENDANCE_LINK");
        const elder = await loadActor(db, before.elderId, tx);
        await elderScope(db, tx, actor, elder, before.householdId);
        const activity = await activityScope(db, tx, actor, before.activityId);
        return {activity, before};
      }, execute: async (tx, _actor, {activity, before}) => {
        const now = clock(); finishedActivity(activity, now);
        const lockRef = db.doc(`activityElderLocks/${activityLockId(before.activityId, before.elderId)}`);
        const lock = (await tx.get(lockRef)).data();
        const managed = await sessionSource(db, tx, before.activityId, before.elderId, lock, before);
        if (managed && decision === "verify") return envelope({attendance: wireRecord(id, before)});
        if (before.mode !== "standalone" || before.status !== "submitted") fail("failed-precondition", "ATTENDANCE_ALREADY_REVIEWED");
        const next = {...before, status: decision === "verify" ? "verified" : "rejected", verifiedAt: decision === "verify" ? now : null,
          verificationMethod: input.verificationMethod, reviewedBy: uid, reviewedAt: now, reviewNote: note, updatedAt: now};
        if (decision === "verify") Object.assign(next, await completeActivityAttendance(db, tx, id, before, now));
        tx.set(db.doc(`activityAttendances/${id}`), next);
        tx.set(lockRef, {activityId: before.activityId, elderId: before.elderId, townshipId: before.townshipId,
          requestId: null, attendanceId: id, state: decision === "verify" ? "completed" : "attendance_rejected", updatedAt: now});
        return envelope({attendance: wireRecord(id, next)});
      }});
  }
  return {submitActivityAttendance, reviewActivityAttendance};
}
