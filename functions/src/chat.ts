import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {loadActor, requireTownship} from "./auth";
import {runCommand, tupleId} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject, integerField, stringField} from "./validation";
import {wireRecord} from "./scheduling";

const chatStates = ["assigned", "accepted", "in_progress", "awaiting_confirmation", "completed"];

async function chatRequest(db: Firestore, tx: Transaction, uid: string, requestId: string) {
  const request = (await tx.get(db.doc(`requests/${requestId}`))).data();
  if (!request) fail("not-found", "REQUEST_NOT_FOUND");
  const actor = await loadActor(db, uid, tx);
  requireTownship(actor, request.townshipId);
  if (!["elder", "helper"].includes(actor.role) ||
      (actor.role === "elder" && request.elderId !== uid) ||
      (actor.role === "helper" && request.helperId !== uid)) {
    fail("permission-denied", "CHAT_PARTICIPANT_REQUIRED");
  }
  if (!request.helperId || !chatStates.includes(request.state)) {
    fail("failed-precondition", "SESSION_NOT_CHATABLE");
  }
  return {request, actor};
}

export function createChatService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function listSessionMessages(uid: string, value: unknown) {
    const input = inputObject(value, ["requestId", "limit"], false);
    const requestId = documentId(input.requestId);
    const requestedLimit = input.limit === undefined ? 100 : integerField(input.limit, "INVALID_LIMIT", 1, 100);
    await db.runTransaction(async (tx) => chatRequest(db, tx, uid, requestId));
    const snapshots = await db.collection("sessionMessages")
      .where("requestId", "==", requestId)
      .orderBy("createdAt", "asc")
      .limit(requestedLimit)
      .get();
    return envelope({messages: snapshots.docs.map((snapshot) => wireRecord(snapshot.id, snapshot.data()))});
  }

  async function sendSessionMessage(uid: string, value: unknown) {
    const input = inputObject(value, ["requestId", "text"], true);
    const requestId = documentId(input.requestId);
    const text = stringField(input.text, "INVALID_MESSAGE", 1000).trim();
    const id = tupleId("session-message", uid, input.idempotencyKey as string);
    return runCommand({
      db, uid, name: "sendSessionMessage", key: input.idempotencyKey as string,
      payload: {requestId, text},
      authorize: async (tx) => chatRequest(db, tx, uid, requestId),
      execute: async (tx, actor, access: {request: DocumentData}) => {
        const ref = db.doc(`sessionMessages/${id}`), existing = await tx.get(ref);
        if (existing.exists) return envelope({message: wireRecord(id, existing.data()!)});
        const now = clock();
        const message = {
          requestId, townshipId: access.request.townshipId,
          elderId: access.request.elderId, helperId: access.request.helperId,
          senderUid: actor.uid, senderRole: actor.role, text,
          createdAt: now,
        };
        tx.create(ref, message);
        return envelope({message: wireRecord(id, message)});
      },
    });
  }

  return {listSessionMessages, sendSessionMessage};
}
