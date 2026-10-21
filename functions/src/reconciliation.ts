import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {attendanceId, completionId, participationId} from "./completion_ids";
import {documentId} from "./validation";
import {fail} from "./errors";
import {prepareReward, RewardAction, RewardContext, rewardActions} from "./rewards";

function verifiedSession(request: DocumentData | undefined, id: string, participant: DocumentData, eventId: string) {
  return request?.state === "completed" && request.townshipId === participant.townshipId &&
    request.elderId !== request.helperId && request.elderConfirmation?.uid === request.elderId &&
    request.helperConfirmation?.uid === request.helperId && request.completedAt instanceof Timestamp &&
    request.completionEventId === eventId && request.participationIds?.[participant.beneficiaryRole] === id &&
    request[participant.beneficiaryRole === "elder" ? "elderId" : "helperId"] === participant.beneficiaryUid;
}

async function verifiedContext(db: Firestore, tx: Transaction, id: string, now: Timestamp): Promise<RewardContext> {
  const participant = (await tx.get(db.doc(`participations/${id}`))).data();
  if (!participant || !["elder", "helper"].includes(participant.beneficiaryRole) || !(participant.verifiedAt instanceof Timestamp) ||
      participant.verifiedAt.toMillis() > now.toMillis()) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
  const eventId = documentId(participant.completionEventId), uid = documentId(participant.beneficiaryUid);
  if (id !== participationId(eventId, uid)) fail("failed-precondition", "INVALID_PARTICIPATION_LINK");
  const event = (await tx.get(db.doc(`completionEvents/${eventId}`))).data();
  if (!event || event.townshipId !== participant.townshipId) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
  let action: RewardAction;
  if (event.eventType === "activity_occurrence") {
    const activityId = documentId(event.activityId);
    const activity = (await tx.get(db.doc(`activities/${activityId}`))).data();
    if (eventId !== completionId(activityId, "") || participant.activityId !== activityId ||
        !activity || activity.participationMode !== "in_person" || activity.townshipId !== participant.townshipId ||
        !(activity.endsAt instanceof Timestamp) || activity.endsAt.toMillis() > participant.verifiedAt.toMillis()) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
    if (participant.beneficiaryRole === "elder") {
      const key = attendanceId(activityId, uid);
      const attendance = (await tx.get(db.doc(`activityAttendances/${key}`))).data();
      if (participant.attendanceId !== key || attendance?.status !== "verified" || attendance.elderId !== uid ||
          attendance.activityId !== activityId || attendance.townshipId !== participant.townshipId ||
          attendance.participationId !== id || attendance.completionEventId !== eventId) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
      if (attendance.mode === "standalone") {
        if (!["organizer_roster", "coordinator_observed"].includes(attendance.verificationMethod) ||
            typeof attendance.reviewedBy !== "string" || !(attendance.reviewedAt instanceof Timestamp)) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
      } else {
        const request = (await tx.get(db.doc(`requests/${documentId(attendance.linkedRequestId)}`))).data();
        if (attendance.mode !== "companion_session" || attendance.verificationMethod !== "mutual_session_confirmation" ||
            request?.activityId !== activityId || !verifiedSession(request, id, participant, eventId)) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
      }
    } else {
      let valid = false;
      for (const requestId of participant.sourceRequestIds ?? []) {
        const request = (await tx.get(db.doc(`requests/${documentId(requestId)}`))).data();
        if (request?.activityId === activityId && verifiedSession(request, id, participant, eventId)) valid = true;
      }
      if (!valid) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
    }
    action = "activity_attendance";
  } else {
    const requestId = documentId(event.requestId);
    const request = (await tx.get(db.doc(`requests/${requestId}`))).data();
    if (event.eventType !== "help_session" || eventId !== completionId(null, requestId) || participant.activityId !== null ||
        !participant.sourceRequestIds?.includes(requestId) || request?.activityId !== null ||
        !rewardActions.includes(request.taskType) || request.taskType === "activity_attendance" ||
        !verifiedSession(request, id, participant, eventId)) fail("failed-precondition", "COMPLETION_NOT_VERIFIED");
    action = request.taskType;
  }
  return {participationId: id, completionEventId: eventId, uid, role: participant.beneficiaryRole,
    townshipId: participant.townshipId, action, verifiedAt: participant.verifiedAt};
}

// Internal only: no callable, no caller-supplied coins or policy. Rechecks the
// actual verified source before settling a missing/pending claim.
export async function reconcileVerifiedParticipation(db: Firestore, id: string, clock: () => Timestamp = Timestamp.now) {
  documentId(id);
  await db.runTransaction(async (tx) => {
    const now = clock(), context = await verifiedContext(db, tx, id, now);
    const before = (await tx.get(db.doc(`rewardClaims/${id}`))).data();
    const reward = await prepareReward(db, tx, context, now, before);
    reward();
  });
  return (await db.doc(`rewardClaims/${id}`).get()).data()!;
}
