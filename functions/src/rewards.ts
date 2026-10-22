import {DocumentData, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {loadActor} from "./auth";
import {tupleId} from "./commands";
import {fail} from "./errors";

export const rewardActions = ["activity_attendance", "walk_with_me", "sit_with_me", "carry_light_item", "phone_help"] as const;
export type RewardAction = typeof rewardActions[number];
export interface RewardContext {
  participationId: string; completionEventId: string; uid: string; role: "elder" | "helper";
  townshipId: string; action: RewardAction; verifiedAt: Timestamp;
}
interface Decision {status: "pending_policy" | "ineligible" | "credited"; reason: string; amountCoins: number | null;
  eligible: boolean | null; ruleId: string | null; ruleVersion: string | null; rateCoins: number | null}
const pending = (reason = "REWARD_POLICY_PENDING"): Decision => ({status: "pending_policy", reason,
  eligible: null, amountCoins: null, ruleId: null, ruleVersion: null, rateCoins: null});
const text = (value: unknown, max = 200): value is string => typeof value === "string" && value.trim().length > 0 && value.length <= max;

// Configuration supplies all eligibility and rates. There are no product rate
// defaults, monthly thresholds, or inferred phone-help eligibility here.
export function evaluatePolicy(policy: DocumentData | undefined, context: Pick<RewardContext, "role" | "action" | "verifiedAt" | "townshipId">): Decision {
  if (!policy || policy.status !== "approved") return pending();
  if (policy.townshipId !== context.townshipId || !text(policy.version, 64) || !text(policy.approvedBy) ||
      !text(policy.approvalReference, 500) || !(policy.approvedAt instanceof Timestamp) ||
      !(policy.effectiveFrom instanceof Timestamp) || !(policy.effectiveUntil === null || policy.effectiveUntil instanceof Timestamp) ||
      (policy.effectiveUntil && policy.effectiveUntil.toMillis() <= policy.effectiveFrom.toMillis()) ||
      !Array.isArray(policy.rules) || policy.rules.length === 0 || policy.rules.length > 64) return pending("REWARD_POLICY_INVALID");
  const ids = new Set<string>();
  for (const rule of policy.rules) {
    if (!rule || !text(rule.id, 128) || ids.has(rule.id) || !rewardActions.includes(rule.action) ||
        !["elder", "helper"].includes(rule.role) || ![true, false, null].includes(rule.eligible) || !text(rule.reason, 128) ||
        (rule.eligible === true ? !Number.isSafeInteger(rule.rateCoins) || rule.rateCoins <= 0 : rule.rateCoins !== null)) {
      return pending("REWARD_POLICY_INVALID");
    }
    ids.add(rule.id);
  }
  if (context.verifiedAt.toMillis() < policy.effectiveFrom.toMillis() ||
      (policy.effectiveUntil && context.verifiedAt.toMillis() >= policy.effectiveUntil.toMillis())) return pending("REWARD_POLICY_NOT_APPLICABLE");
  const rules = policy.rules.filter((rule: DocumentData) => rule.role === context.role && rule.action === context.action);
  if (rules.length > 1) return pending("REWARD_RULE_AMBIGUOUS");
  const rule = rules[0];
  if (!rule || rule.eligible === null) return pending();
  return {status: rule.eligible ? "credited" : "ineligible", eligible: rule.eligible,
    amountCoins: rule.eligible ? rule.rateCoins : 0, ruleId: rule.id, ruleVersion: policy.version,
    rateCoins: rule.eligible ? rule.rateCoins : null, reason: rule.reason};
}

export function rewardEntryId(id: string): string { return tupleId("completion-reward", id); }

export function walletBalance(wallet: DocumentData | undefined, uid: string, townshipId: string): number {
  if (!wallet) fail("failed-precondition", "WALLET_REQUIRED");
  if (wallet.ownerUid !== uid || wallet.townshipId !== townshipId) fail("permission-denied", "WALLET_ACCESS_DENIED");
  if (!Number.isSafeInteger(wallet.balance) || wallet.balance < 0) fail("failed-precondition", "INVALID_WALLET_BALANCE");
  return wallet.balance;
}

// Return a write-only effect so callers can finish ALL participants' reads
// before creating domain records or applying any credit in their transaction.
export async function prepareReward(db: Firestore, tx: Transaction, context: RewardContext, now: Timestamp, before: DocumentData | undefined) {
  const {uid, townshipId, participationId: id, completionEventId} = context;
  const owner = await loadActor(db, uid, tx);
  if (owner.role !== context.role || owner.townshipId !== townshipId) fail("failed-precondition", "REWARD_RECIPIENT_MISMATCH");
  const entryId = rewardEntryId(id), entryRef = db.doc(`wallets/${uid}/entries/${entryId}`);
  const entry = (await tx.get(entryRef)).data();
  const claimRef = db.doc(`rewardClaims/${id}`);
  const base = {participationId: id, completionEventId, beneficiaryUid: uid, beneficiaryRole: context.role, townshipId,
    verifiedAt: context.verifiedAt, createdAt: before?.createdAt ?? now, updatedAt: now};
  if (before && (before.beneficiaryUid !== uid || before.townshipId !== townshipId ||
      before.participationId !== id || before.completionEventId !== completionEventId)) fail("failed-precondition", "REWARD_ACCOUNTING_CONFLICT");
  if (entry) {
    if (entry.type !== "completion_reward" || entry.ownerUid !== uid || entry.townshipId !== townshipId ||
        entry.participationId !== id || entry.completionEventId !== completionEventId ||
        !Number.isSafeInteger(entry.amount) || entry.amount <= 0 || entry.rateCoins !== entry.amount ||
        !text(entry.ruleId) || !text(entry.ruleVersion) || !(entry.createdAt instanceof Timestamp) ||
        !Number.isSafeInteger(entry.balanceAfter) || entry.balanceAfter < entry.amount || before?.status === "ineligible") {
      fail("failed-precondition", "REWARD_ACCOUNTING_CONFLICT");
    }
    const wallet = (await tx.get(db.doc(`wallets/${uid}`))).data(); walletBalance(wallet, uid, townshipId);
    if (before?.status === "credited") {
      if (before.ledgerEntryId !== entryId || before.amountCoins !== entry.amount || before.ruleId !== entry.ruleId || before.ruleVersion !== entry.ruleVersion) {
        fail("failed-precondition", "REWARD_ACCOUNTING_CONFLICT");
      }
      return () => {};
    }
    return () => tx.set(claimRef, {...base, status: "credited", eligible: true, amountCoins: entry.amount,
      rateCoins: entry.rateCoins, ruleId: entry.ruleId, ruleVersion: entry.ruleVersion, ledgerEntryId: entryId, reason: "RECOVERED_REWARD_ENTRY"});
  }
  if (before?.status === "credited") fail("failed-precondition", "REWARD_ACCOUNTING_CONFLICT");
  if (before?.status === "ineligible") return () => {};
  const pointer = (await tx.get(db.doc(`rewardPolicies/${townshipId}`))).data();
  let policy: DocumentData | undefined;
  let invalidReference = false;
  if (pointer?.activeVersionId) {
    if (typeof pointer.activeVersionId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(pointer.activeVersionId)) {
      invalidReference = true;
    } else policy = (await tx.get(db.doc(`rewardPolicyVersions/${pointer.activeVersionId}`))).data();
  }
  const decision = invalidReference ? pending("REWARD_POLICY_INVALID") : evaluatePolicy(policy, context);
  if (decision.status === "pending_policy" && before?.status === "pending_policy") return () => {};
  if (decision.status !== "credited") return () => tx.set(claimRef, {...base, ...decision, ledgerEntryId: null});
  const walletRef = db.doc(`wallets/${uid}`), wallet = (await tx.get(walletRef)).data();
  const balance = walletBalance(wallet, uid, townshipId) + decision.amountCoins!;
  if (!Number.isSafeInteger(balance)) fail("failed-precondition", "INVALID_WALLET_BALANCE");
  return () => {
    tx.create(entryRef, {ownerUid: uid, townshipId, type: "completion_reward", amount: decision.amountCoins, balanceAfter: balance,
      participationId: id, completionEventId, ruleId: decision.ruleId, ruleVersion: decision.ruleVersion,
      rateCoins: decision.rateCoins, referenceId: id, createdAt: now});
    tx.set(walletRef, {ownerUid: uid, townshipId, balance, updatedAt: now});
    tx.set(claimRef, {...base, ...decision, ledgerEntryId: entryId});
  };
}
