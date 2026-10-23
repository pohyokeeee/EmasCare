import {DocumentData, Firestore, Timestamp, Transaction, DocumentReference, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {requireRole} from "./auth";
import {runCommand} from "./commands";
import {fail} from "./errors";
import {envelope, inputObject} from "./validation";
import {rewardEntryId, walletBalance} from "./rewards";

type ClaimRow = {id: string; ref: DocumentReference; data: DocumentData};

function validClaim(claim: DocumentData, townshipId: string, now: Timestamp): void {
  if (claim.townshipId !== townshipId || claim.status !== "pending_monthly" || claim.eligible !== true ||
      !["elder", "helper"].includes(claim.beneficiaryRole) || typeof claim.beneficiaryUid !== "string" ||
      !Number.isSafeInteger(claim.amountCoins) || claim.amountCoins <= 0 ||
      !Number.isSafeInteger(claim.rateCoins) || claim.rateCoins !== claim.amountCoins ||
      typeof claim.ruleId !== "string" || typeof claim.ruleVersion !== "string" ||
      claim.ledgerEntryId !== null || claim.releasedAt !== null ||
      !(claim.releaseAt instanceof Timestamp) || claim.releaseAt.toMillis() > now.toMillis() ||
      typeof claim.rewardMonth !== "string" || !/^\d{4}-\d\d$/.test(claim.rewardMonth)) {
    fail("failed-precondition", "INVALID_MONTHLY_REWARD");
  }
}

function validEntry(entry: DocumentData, claim: DocumentData): void {
  if (entry.type !== "completion_reward" || entry.ownerUid !== claim.beneficiaryUid ||
      entry.townshipId !== claim.townshipId || entry.participationId !== claim.participationId ||
      entry.completionEventId !== claim.completionEventId || entry.amount !== claim.amountCoins ||
      entry.rateCoins !== claim.rateCoins || entry.ruleId !== claim.ruleId ||
      entry.ruleVersion !== claim.ruleVersion || entry.referenceId !== claim.participationId ||
      !Number.isSafeInteger(entry.balanceAfter) || entry.balanceAfter < entry.amount ||
      !Number.isSafeInteger(entry.amount) || entry.amount <= 0) {
    fail("failed-precondition", "REWARD_ACCOUNTING_CONFLICT");
  }
}

async function settleRows(db: Firestore, tx: Transaction, townshipId: string,
  claimSnapshots: QueryDocumentSnapshot[], now: Timestamp) {
  const claimRows: ClaimRow[] = claimSnapshots
    .filter((snapshot) => snapshot.data().townshipId === townshipId)
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((snapshot) => ({id: snapshot.id, ref: snapshot.ref, data: snapshot.data()}));
  if (claimRows.length === 0) return {settledClaims: 0, totalCoins: 0};
  for (const row of claimRows) validClaim(row.data, townshipId, now);

  const walletRefs = [...new Map(claimRows.map((row) => [row.data.beneficiaryUid,
    db.doc(`wallets/${row.data.beneficiaryUid}`)])).values()];
  const entryRefs = claimRows.map((row) => db.doc(`wallets/${row.data.beneficiaryUid}/entries/${rewardEntryId(row.id)}`));
  const userRefs = [...new Map(claimRows.map((row) => [row.data.beneficiaryUid,
    db.doc(`users/${row.data.beneficiaryUid}`)])).values()];
  const walletSnapshots = await tx.getAll(...walletRefs);
  const entrySnapshots = await tx.getAll(...entryRefs);
  const userSnapshots = await tx.getAll(...userRefs);
  const wallets = new Map(walletSnapshots.map((snapshot) => [snapshot.id, snapshot.data()]));
  const profiles = new Map(userSnapshots.map((snapshot) => [snapshot.id, snapshot.data()]));
  const balances = new Map<string, number>();
  for (const [ownerUid, wallet] of wallets) balances.set(ownerUid, walletBalance(wallet, ownerUid, townshipId));
  let settledClaims = 0, totalCoins = 0;
  for (let i = 0; i < claimRows.length; i++) {
    const {id, ref, data: claim} = claimRows[i]!;
    const owner = profiles.get(claim.beneficiaryUid);
    if (!owner || owner.role !== claim.beneficiaryRole || owner.townshipId !== townshipId) {
      fail("failed-precondition", "REWARD_RECIPIENT_MISMATCH");
    }
    const entryRef = entryRefs[i]!, existing = entrySnapshots[i]!.data();
    const entryId = rewardEntryId(id);
    if (existing) {
      validEntry(existing, claim);
      tx.update(ref, {status: "credited", ledgerEntryId: entryId, releasedAt: now, updatedAt: now});
    } else {
      const opening = balances.get(claim.beneficiaryUid) ?? 0;
      const balance = opening + claim.amountCoins;
      if (!Number.isSafeInteger(balance)) fail("failed-precondition", "INVALID_WALLET_BALANCE");
      tx.create(entryRef, {ownerUid: claim.beneficiaryUid, townshipId,
        type: "completion_reward", amount: claim.amountCoins, balanceAfter: balance,
        participationId: claim.participationId, completionEventId: claim.completionEventId,
        ruleId: claim.ruleId, ruleVersion: claim.ruleVersion, rateCoins: claim.rateCoins,
        referenceId: claim.participationId, createdAt: now});
      const walletRef = db.doc(`wallets/${claim.beneficiaryUid}`);
      tx.set(walletRef, {ownerUid: claim.beneficiaryUid, townshipId,
        balance, updatedAt: now}, {merge: true});
      balances.set(claim.beneficiaryUid, balance);
      tx.update(ref, {status: "credited", ledgerEntryId: entryId, releasedAt: now, updatedAt: now});
    }
    settledClaims++;
    totalCoins += claim.amountCoins;
  }
  return {settledClaims, totalCoins};
}

export function createMonthlyRewardService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function dueClaims(townshipId: string, now: Timestamp, tx?: Transaction) {
    const query = db.collection("rewardClaims")
      .where("townshipId", "==", townshipId)
      .where("status", "==", "pending_monthly")
      .where("releaseAt", "<=", now);
    return tx ? (await tx.get(query)).docs : (await query.get()).docs;
  }

  async function settleDueMonthlyRewards(uid: string, value: unknown) {
    const input = inputObject(value, [], true);
    return runCommand({
      db, uid, name: "settleDueMonthlyRewards", key: input.idempotencyKey as string,
      payload: {},
      authorize: async (_tx, actor) => { requireRole(actor, ["coordinator"]); return actor; },
      execute: async (tx, actor) => {
        const now = clock();
        const claims = await dueClaims(actor.townshipId, now, tx);
        const result = await settleRows(db, tx, actor.townshipId, claims, now);
        return envelope({...result, processedAt: now.toDate().toISOString()});
      },
    });
  }

  /** Deployment-only safety net; the callable remains available for the demo. */
  async function settleDueMonthlyRewardsScheduled() {
    const now = clock();
    const snapshots = await db.collection("rewardClaims")
      .where("status", "==", "pending_monthly")
      .where("releaseAt", "<=", now)
      .get();
    const townships = [...new Set(snapshots.docs.map((snapshot) => snapshot.data().townshipId as string))]
      .filter(Boolean).sort();
    let settledClaims = 0, totalCoins = 0;
    for (const townshipId of townships) {
      const result = await db.runTransaction(async (tx) => {
        const claims = await dueClaims(townshipId, now, tx);
        return settleRows(db, tx, townshipId, claims, now);
      });
      settledClaims += result.settledClaims;
      totalCoins += result.totalCoins;
    }
    return {settledClaims, totalCoins, processedAt: now.toDate().toISOString(), townships};
  }

  return {settleDueMonthlyRewards, settleDueMonthlyRewardsScheduled};
}
