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

interface Beneficiary {uid: string; role: "elder" | "helper"; attendanceId: string | null}

// Both evidence paths use the same event, participant, claim and progress keys.
// All reads complete before any writes; existing claims are never overwritten.
async function recordCompletion(db: Firestore, tx: Transaction, eventId: string, townshipId: string,
  activityId: string | null, requestId: string | null, beneficiaries: Beneficiary[], classification: string, now: Timestamp) {
  const eventRef = db.doc(`completionEvents/${eventId}`);
  const event = await tx.get(eventRef);
  const rows = [];
  for (const beneficiary of beneficiaries) {
    const id = participationId(eventId, beneficiary.uid);
    const refs = [db.doc(`participations/${id}`), db.doc(`rewardClaims/${id}`), db.doc(`completionMarkers/${id}`)];
    const snapshots = await tx.getAll(...refs);
    rows.push({beneficiary, id, refs, snapshots});
  }
  if (!event.exists) tx.create(eventRef, {townshipId, eventType: activityId ? "activity_occurrence" : "help_session",
    activityId, requestId: activityId ? null : requestId, firstVerifiedAt: now, createdAt: now, updatedAt: now});
  for (const {beneficiary, id, refs, snapshots} of rows) {
    const {uid, role} = beneficiary;
    const before = snapshots[0]!.data();
    const verifiedAt = before?.verifiedAt ?? now;
    tx.set(refs[0]!, {...before, completionEventId: eventId, townshipId, beneficiaryUid: uid, beneficiaryRole: role,
      activityId, sourceRequestIds: [...new Set([...(before?.sourceRequestIds ?? []), ...(requestId ? [requestId] : [])])],
      attendanceId: beneficiary.attendanceId, verifiedAt, outingClassification: classification,
      createdAt: before?.createdAt ?? now, updatedAt: now});
    if (!snapshots[1]!.exists) tx.create(refs[1]!, {participationId: id, completionEventId: eventId,
      beneficiaryUid: uid, beneficiaryRole: role, townshipId, status: "pending_policy",
      eligible: null, amountCoins: null, ruleId: null, ruleVersion: null, rateCoins: null, ledgerEntryId: null,
      reason: "REWARD_POLICY_PENDING", verifiedAt, createdAt: now, updatedAt: now});
    if (!snapshots[2]!.exists) tx.create(refs[2]!, {participationId: id, completionEventId: eventId,
      beneficiaryUid: uid, beneficiaryRole: role, townshipId, outingClassification: classification, verifiedAt});
  }
}

export async function completeSession(db: Firestore, tx: Transaction, id: string, request: DocumentData, now: Timestamp) {
  const eventId = completionId(request.activityId, id);
  const ids = {elder: participationId(eventId, request.elderId), helper: participationId(eventId, request.helperId)};
  const attendanceKey = request.activityId ? attendanceId(request.activityId, request.elderId) : null;
  const attendance = attendanceKey ? (await tx.get(db.doc(`activityAttendances/${attendanceKey}`))).data() : undefined;
  if (attendance?.status === "rejected") fail("failed-precondition", "ATTENDANCE_ALREADY_REVIEWED");
  const classification = request.activityId || request.taskType === "walk_with_me" ? "counts" :
    request.taskType === "phone_help" ? "does_not_count" : "pending_definition";
  await recordCompletion(db, tx, eventId, request.townshipId, request.activityId, id, [
    {uid: request.elderId, role: "elder", attendanceId: attendanceKey},
    {uid: request.helperId, role: "helper", attendanceId: null},
  ], classification, now);
  if (attendanceKey && attendance?.status !== "verified") tx.set(db.doc(`activityAttendances/${attendanceKey}`), {townshipId: request.townshipId,
    householdId: request.householdId, activityId: request.activityId, elderId: request.elderId,
    mode: "companion_session", status: "verified", linkedRequestId: id, submittedAt: null,
    verifiedAt: attendance?.verifiedAt ?? now, verificationMethod: "mutual_session_confirmation",
    reviewedBy: null, reviewedAt: null, reviewNote: null, completionEventId: eventId, participationId: ids.elder,
    createdAt: attendance?.createdAt ?? now, updatedAt: now});
  return {completionEventId: eventId, participationIds: ids};
}

export async function completeActivityAttendance(db: Firestore, tx: Transaction, id: string, attendance: DocumentData, now: Timestamp) {
  const eventId = completionId(attendance.activityId, id);
  const participantId = participationId(eventId, attendance.elderId);
  await recordCompletion(db, tx, eventId, attendance.townshipId, attendance.activityId, null,
    [{uid: attendance.elderId, role: "elder", attendanceId: id}], "counts", now);
  return {completionEventId: eventId, participationId: participantId};
}
