import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {tupleId} from "./commands";
import {fail} from "./errors";

export function activityLockId(activityId: string, elderId: string): string {
  return tupleId("activity-elder", activityId, elderId);
}
export function attendanceId(activityId: string, elderId: string): string {
  return tupleId("attendance", activityId, elderId);
}
export function completionId(activityId: string | null, requestId: string): string {
  return activityId ? tupleId("activity", activityId) : tupleId("help-session", requestId);
}
export function participationId(eventId: string, uid: string): string {
  return tupleId("participation", eventId, uid);
}

// Shared canonical identities for companion completion and the Stage 4 standalone
// path. Reads finish before writes. No coin rate or public award action is added.
export async function completeSession(db: Firestore, tx: Transaction, id: string, request: DocumentData, now: Timestamp) {
  const eventId = completionId(request.activityId, id);
  const ids = {elder: participationId(eventId, request.elderId), helper: participationId(eventId, request.helperId)};
  const eventRef = db.doc(`completionEvents/${eventId}`);
  const elderRef = db.doc(`participations/${ids.elder}`);
  const helperRef = db.doc(`participations/${ids.helper}`);
  const elderClaim = db.doc(`rewardClaims/${ids.elder}`);
  const helperClaim = db.doc(`rewardClaims/${ids.helper}`);
  const snapshots = await tx.getAll(eventRef, elderRef, helperRef, elderClaim, helperClaim,
    db.doc(`completionMarkers/${ids.elder}`), db.doc(`completionMarkers/${ids.helper}`));
  let attendance: DocumentData | undefined;
  const attendanceKey = request.activityId ? attendanceId(request.activityId, request.elderId) : null;
  if (attendanceKey) attendance = (await tx.get(db.doc(`activityAttendances/${attendanceKey}`))).data();
  if (attendance?.status === "rejected") fail("failed-precondition", "ATTENDANCE_ALREADY_REVIEWED");
  const classification = request.activityId || request.taskType === "walk_with_me" ? "counts" :
    request.taskType === "phone_help" ? "does_not_count" : "pending_definition";
  if (!snapshots[0]!.exists) tx.create(eventRef, {townshipId: request.townshipId,
    eventType: request.activityId ? "activity_occurrence" : "help_session", activityId: request.activityId,
    requestId: request.activityId ? null : id, firstVerifiedAt: now, createdAt: now, updatedAt: now});
  for (const [index, role, uid, ref, claimRef, participantId] of [
    [1, "elder", request.elderId, elderRef, elderClaim, ids.elder],
    [2, "helper", request.helperId, helperRef, helperClaim, ids.helper],
  ] as const) {
    const before = snapshots[index]!.data();
    const verifiedAt = before?.verifiedAt ?? now;
    tx.set(ref, {...before, completionEventId: eventId, townshipId: request.townshipId, beneficiaryUid: uid, beneficiaryRole: role,
      activityId: request.activityId, sourceRequestIds: [...new Set([...(before?.sourceRequestIds ?? []), id])],
      attendanceId: role === "elder" ? attendanceKey : null, verifiedAt, outingClassification: classification,
      createdAt: before?.createdAt ?? now, updatedAt: now});
    if (!snapshots[index + 2]!.exists) tx.create(claimRef, {participationId: participantId, completionEventId: eventId,
      beneficiaryUid: uid, beneficiaryRole: role, townshipId: request.townshipId, status: "pending_policy",
      eligible: null, amountCoins: null, ruleId: null, ruleVersion: null, rateCoins: null, ledgerEntryId: null,
      reason: "REWARD_POLICY_PENDING", verifiedAt, createdAt: now, updatedAt: now});
    if (!snapshots[index + 4]!.exists) tx.create(db.doc(`completionMarkers/${participantId}`),
      {participationId: participantId, completionEventId: eventId, beneficiaryUid: uid, beneficiaryRole: role,
        townshipId: request.townshipId, outingClassification: classification, verifiedAt});
  }
  if (attendanceKey && attendance?.status !== "verified") tx.set(db.doc(`activityAttendances/${attendanceKey}`), {townshipId: request.townshipId,
    householdId: request.householdId, activityId: request.activityId, elderId: request.elderId,
    mode: "companion_session", status: "verified", linkedRequestId: id, submittedAt: null,
    verifiedAt: attendance?.verifiedAt ?? now, verificationMethod: "mutual_session_confirmation",
    reviewedBy: null, reviewedAt: null, reviewNote: null, completionEventId: eventId, participationId: ids.elder,
    createdAt: attendance?.createdAt ?? now, updatedAt: now});
  return {completionEventId: eventId, participationIds: ids};
}
