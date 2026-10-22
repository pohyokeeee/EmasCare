import {Firestore, Timestamp} from "firebase-admin/firestore";
import {requireRole} from "./auth";
import {runCommand, tupleId} from "./commands";
import {fail} from "./errors";
import {walletBalance} from "./rewards";
import {wireRecord} from "./scheduling";
import {documentId, envelope, inputObject} from "./validation";

export function redemptionId(uid: string, key: string): string { return tupleId("redemption", uid, key); }
export function redemptionEntryId(id: string): string { return tupleId("voucher-redemption", id); }
export function demoVoucherCode(id: string): string { return `DEMO-${id.slice(0, 24).toUpperCase()}`; }

export function createWalletService(db: Firestore, clock: () => Timestamp = Timestamp.now) {
  async function redeemDemoVoucher(uid: string, value: unknown) {
    const input = inputObject(value, ["voucherId"], true), voucherId = documentId(input.voucherId);
    const id = redemptionId(uid, input.idempotencyKey as string), entryId = redemptionEntryId(id);
    return runCommand({db, uid, name: "redeemDemoVoucher", key: input.idempotencyKey as string, payload: {voucherId},
      authorize: async (tx, actor) => {
        requireRole(actor, ["elder", "helper"]);
        const wallet = (await tx.get(db.doc(`wallets/${actor.uid}`))).data();
        return walletBalance(wallet, actor.uid, actor.townshipId);
      }, execute: async (tx, actor, openingBalance) => {
        const catalog = (await tx.get(db.doc(`voucherCatalog/${voucherId}`))).data();
        if (!catalog) fail("not-found", "VOUCHER_NOT_FOUND");
        if (catalog.townshipId !== actor.townshipId) fail("permission-denied", "TOWNSHIP_NOT_ALLOWED");
        if (catalog.active !== true || catalog.isDemo !== true) fail("failed-precondition", "VOUCHER_NOT_AVAILABLE");
        if (catalog.costCoins !== 100) fail("failed-precondition", "INVALID_VOUCHER_PRICE");
        if (openingBalance < catalog.costCoins) fail("failed-precondition", "INSUFFICIENT_BALANCE");
        const now = clock(), balance = openingBalance - catalog.costCoins;
        const redemptionRef = db.doc(`redemptions/${id}`), entryRef = db.doc(`wallets/${uid}/entries/${entryId}`);
        const prior = await tx.getAll(redemptionRef, entryRef);
        if (prior.some((snapshot) => snapshot.exists)) fail("failed-precondition", "REDEMPTION_ACCOUNTING_CONFLICT");
        const redemption = {ownerUid: uid, townshipId: actor.townshipId, voucherId, costCoins: catalog.costCoins,
          code: demoVoucherCode(id), ledgerEntryId: entryId, issuedAt: now, isDemo: true};
        tx.create(redemptionRef, redemption);
        tx.create(entryRef, {ownerUid: uid, townshipId: actor.townshipId, type: "voucher_redemption", amount: -catalog.costCoins,
          balanceAfter: balance, participationId: null, completionEventId: null, ruleId: null, ruleVersion: null,
          rateCoins: null, referenceId: id, createdAt: now});
        tx.set(db.doc(`wallets/${uid}`), {ownerUid: uid, townshipId: actor.townshipId, balance, updatedAt: now});
        return envelope({redemption: wireRecord(id, redemption), entryId, balance});
      }});
  }
  return {redeemDemoVoucher};
}
