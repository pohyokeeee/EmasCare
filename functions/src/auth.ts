import {Firestore, Transaction} from "firebase-admin/firestore";
import {fail} from "./errors";

export const roles = ["elder", "family", "helper", "coordinator"] as const;
export type Role = typeof roles[number];
export interface Actor {
  uid: string;
  displayName: string;
  role: Role;
  townshipId: string;
  householdId: string | null;
  locale: "bm" | "en";
}

export function authenticatedUid(auth: {uid: string} | undefined): string {
  if (!auth) fail("unauthenticated", "AUTH_REQUIRED");
  return auth.uid;
}

// Read inside the mutation transaction, including on receipt replay. Auth token
// custom claims and caller-supplied roles never override the current profile.
export async function loadActor(db: Firestore, uid: string, tx?: Transaction): Promise<Actor> {
  const ref = db.doc(`users/${uid}`);
  const snap = tx ? await tx.get(ref) : await ref.get();
  const p = snap.data();
  if (!p || !roles.includes(p.role) || typeof p.townshipId !== "string" ||
      typeof p.displayName !== "string" || !["bm", "en"].includes(p.locale) ||
      !(p.householdId === null || typeof p.householdId === "string")) {
    fail("permission-denied", "PROFILE_REQUIRED");
  }
  return {uid, displayName: p.displayName, role: p.role, townshipId: p.townshipId,
    householdId: p.householdId, locale: p.locale};
}

export function requireRole(actor: Actor, allowed: readonly Role[]): void {
  if (!allowed.includes(actor.role)) fail("permission-denied", "ROLE_NOT_ALLOWED");
}

export function requireTownship(actor: Actor, townshipId: string): void {
  if (actor.townshipId !== townshipId) fail("permission-denied", "TOWNSHIP_NOT_ALLOWED");
}

export async function authorizeElder(
  db: Firestore, tx: Transaction, actor: Actor, elderId: string,
  scope: "daily_sharing" | "family_booking",
): Promise<void> {
  const elderSnap = await tx.get(db.doc(`users/${elderId}`));
  const elder = elderSnap.data();
  if (!elder || elder.role !== "elder") fail("permission-denied", "ELDER_ACCESS_DENIED");
  requireTownship(actor, elder.townshipId);
  if (actor.role === "coordinator" || (actor.role === "elder" && actor.uid === elderId)) return;
  requireRole(actor, ["family"]);
  if (!actor.householdId || actor.householdId !== elder.householdId) {
    fail("permission-denied", "UNRELATED_HOUSEHOLD");
  }
  const household = (await tx.get(db.doc(`households/${actor.householdId}`))).data();
  if (!household || household.townshipId !== actor.townshipId ||
      !household.memberUids?.includes(actor.uid) || !household.familyUids?.includes(actor.uid) ||
      !household.elderIds?.includes(elderId)) fail("permission-denied", "UNRELATED_HOUSEHOLD");
  const settings = (await tx.get(db.doc(`elderSettings/${elderId}`))).data();
  const flag = scope === "daily_sharing" ? "familySharingEnabled" : "familyBookingEnabled";
  if (settings?.[flag] !== true) fail("permission-denied", "CONSENT_REQUIRED");
}
