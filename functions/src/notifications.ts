import {DocumentData, DocumentReference, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {Actor, authorizeElder, loadActor, requireTownship} from "./auth";
import {runCommand, tupleId} from "./commands";
import {fail} from "./errors";
import {documentId, envelope, inputObject} from "./validation";

export interface Notice {
  recipientUid: string; elderId: string; kind: string; entityId: string;
  consentScope: "daily_sharing" | "family_booking" | "none"; messageParams: Record<string, string>;
}

export async function familyRecipients(db: Firestore, tx: Transaction, elderId: string, scope: "daily_sharing" | "family_booking") {
  const elder = await loadActor(db, elderId, tx);
  const settings = (await tx.get(db.doc(`elderSettings/${elderId}`))).data();
  const flag = scope === "daily_sharing" ? "familySharingEnabled" : "familyBookingEnabled";
  if (!elder.householdId || !settings?.[flag]) return [];
  const household = (await tx.get(db.doc(`households/${elder.householdId}`))).data();
  if (!household || household.townshipId !== elder.townshipId || !household.elderIds?.includes(elderId) || !household.memberUids?.includes(elderId)) return [];
  const ids: string[] = [...new Set<string>(household.familyUids ?? [])];
  if (ids.length > 20) fail("resource-exhausted", "DEMO_LIMIT_EXCEEDED");
  const profiles = ids.length ? await tx.getAll(...ids.map((id) => db.doc(`users/${id}`))) : [];
  return profiles.filter((p) => p.data()?.role === "family" && p.data()?.townshipId === elder.townshipId &&
    p.data()?.householdId === elder.householdId && household.memberUids.includes(p.id)).map((p) => p.id);
}

export async function prepareNotices(db: Firestore, tx: Transaction, notices: Notice[], eventKey: string, now: Timestamp) {
  const rows: {ref: DocumentReference; data: DocumentData}[] = [];
  for (const notice of notices) {
    const id = tupleId("notification", notice.kind, notice.entityId, eventKey, notice.recipientUid);
    const ref = db.doc(`notifications/${id}`), existing = await tx.get(ref);
    if (!existing.exists) rows.push({ref, data: {...notice, readAt: null, createdAt: now}});
  }
  return {count: rows.length, write: () => { for (const row of rows) tx.create(row.ref, row.data); }};
}

export async function prepareElderNotices(db: Firestore, tx: Transaction, elderId: string, kind: string, entityId: string,
  scope: "daily_sharing" | "family_booking", eventKey: string, params: Record<string, string>, now: Timestamp, helperId?: string) {
  const families = await familyRecipients(db, tx, elderId, scope);
  const notices: Notice[] = [elderId, ...(helperId ? [helperId] : [])].map((recipientUid) =>
    ({recipientUid, elderId, kind, entityId, consentScope: "none", messageParams: params}));
  for (const recipientUid of families) notices.push({recipientUid, elderId, kind, entityId, consentScope: scope, messageParams: params});
  return prepareNotices(db, tx, notices, eventKey, now);
}

export async function notificationAccess(db: Firestore, tx: Transaction, actor: Actor, notice: DocumentData) {
  if (notice.recipientUid !== actor.uid) fail("permission-denied", "NOTIFICATION_ACCESS_DENIED");
  const elder = await loadActor(db, documentId(notice.elderId), tx); requireTownship(actor, elder.townshipId);
  if (notice.consentScope === "daily_sharing" || notice.consentScope === "family_booking") {
    if (actor.role !== "family") fail("permission-denied", "NOTIFICATION_ACCESS_DENIED");
    await authorizeElder(db, tx, actor, elder.uid, notice.consentScope);
  } else if (notice.consentScope !== "none" || !(actor.role === "coordinator" || actor.role === "helper" || actor.role === "elder" && actor.uid === elder.uid)) {
    fail("permission-denied", "NOTIFICATION_ACCESS_DENIED");
  }
}

export function createNotificationService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function markNotificationRead(uid: string, value: unknown) {
    const input = inputObject(value, ["notificationId"], true), id = documentId(input.notificationId);
    return runCommand({db, uid, name: "markNotificationRead", key: input.idempotencyKey as string, payload: {notificationId: id},
      authorize: async (tx, actor) => {
        const notice = (await tx.get(db.doc(`notifications/${id}`))).data();
        if (!notice) fail("not-found", "NOTIFICATION_NOT_FOUND");
        await notificationAccess(db, tx, actor, notice); return notice;
      }, execute: async (tx, _actor, notice) => {
        const at = notice.readAt ?? clock();
        if (!notice.readAt) tx.update(db.doc(`notifications/${id}`), {readAt: at});
        return envelope({notificationId: id, readAt: at.toDate().toISOString()});
      }});
  }
  return {markNotificationRead};
}
