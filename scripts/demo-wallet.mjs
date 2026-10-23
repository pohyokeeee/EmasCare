import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {demoClients} from './demo.mjs';

const demoOpeningCoins = 50;
const demoWalletOwners = ['elder_demo', 'helper_demo'];
const entryId = 'demo-opening-50';

export async function prepareDemoWallets(clients) {
  const {db} = clients;
  const now = Timestamp.now();
  for (const uid of demoWalletOwners) {
    const walletRef = db.doc(`wallets/${uid}`);
    const entryRef = db.doc(`wallets/${uid}/entries/${entryId}`);
    const before = (await walletRef.get()).data();
    assert(before?.ownerUid === uid, `Missing demo wallet ${uid}; run npm.cmd run demo:reset first`);
    const existing = (await db.collection(`wallets/${uid}/entries`).get()).docs;
    const opening = (await entryRef.get()).data();
    if (opening?.type === 'demo_opening_credit' && before.balance === demoOpeningCoins) continue;
    assert.equal(existing.length, 0, `Wallet ${uid} already has ledger history; do not overwrite it`);
    assert.equal(before.balance, 0, `Wallet ${uid} is not empty; do not overwrite it`);
    await db.runTransaction(async (tx) => {
      const wallet = (await tx.get(walletRef)).data();
      assert(wallet?.ownerUid === uid && wallet.balance === 0, `Wallet ${uid} changed during demo setup`);
      tx.create(entryRef, {
        ownerUid: uid,
        townshipId: before.townshipId,
        type: 'demo_opening_credit',
        amount: demoOpeningCoins,
        balanceAfter: demoOpeningCoins,
        participationId: null,
        completionEventId: null,
        ruleId: null,
        ruleVersion: 'demo-opening-v1',
        rateCoins: null,
        referenceId: entryId,
        isDemo: true,
        createdAt: now,
      });
      tx.update(walletRef, {balance: demoOpeningCoins, updatedAt: now});
    });
  }
  return {owners: demoWalletOwners, balance: demoOpeningCoins, voucherThreshold: 100};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.argv.length, 2, 'Demo wallet setup accepts no account or amount arguments');
  const clients = await demoClients();
  try {
    const result = await prepareDemoWallets(clients);
    console.log(`Demo wallets ready: ${result.owners.join(', ')} have ${result.balance} coins each.`);
    console.log(`Redemption remains locked until ${result.voucherThreshold} coins.`);
  } finally {
    await clients.db.terminate();
    await deleteApp(clients.app);
  }
}
