// Read-only local client verification; never seeds, resets or changes money.
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,getDocsFromServer,getDocFromServer,collection,doc,query,where,orderBy,terminate} from 'firebase/firestore';
import {localEnvironment,projectId} from '../../scripts/local.mjs';
import {demoAccounts,demoPassword} from '../../scripts/fixtures.mjs';

localEnvironment();
const defaults = process.argv.includes('--expect-default-demo');
let checks=0;
for (const account of demoAccounts) {
  const app=initializeApp({apiKey:'local-demo-key',projectId,appId:'1:1234567890:web:emascare-demo'},`wallet-read-${account.uid}`);
  const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  const db=getFirestore(app);connectFirestoreEmulator(db,'127.0.0.1',8080);
  const read=path=>getDocFromServer(doc(db,path));
  try {
    await signInWithEmailAndPassword(auth,account.email,demoPassword);
    const p=(await read(`users/${account.uid}`)).data();assert.equal(p.role,account.role);checks++;
    await assert.rejects(read(`rewardPolicies/${p.townshipId}`),{code:'permission-denied'});checks++;
    await assert.rejects(getDocsFromServer(collection(db,'rewardClaims')),{code:'permission-denied'});checks++;
    const catalog=await getDocsFromServer(query(collection(db,'voucherCatalog'),where('townshipId','==',p.townshipId)));
    assert(catalog.docs.every(d=>d.data().townshipId===p.townshipId));checks++;
    if (['elder','helper'].includes(p.role)) {
      const wallet=(await read(`wallets/${account.uid}`)).data();
      assert.equal(wallet.ownerUid,account.uid);assert.equal(wallet.townshipId,p.townshipId);
      assert(Number.isSafeInteger(wallet.balance)&&wallet.balance>=0);checks++;
      const rows=[];
      for (const [path,owner,time] of [
        [`wallets/${account.uid}/entries`,'ownerUid','createdAt'],
        ['redemptions','ownerUid','issuedAt'],['rewardClaims','beneficiaryUid','verifiedAt'],
      ]) {
        const snapshot=await getDocsFromServer(query(collection(db,path),where(owner,'==',account.uid),where('townshipId','==',p.townshipId),orderBy(time,'desc')));
        assert(snapshot.docs.every(d=>d.data()[owner]===account.uid&&d.data().townshipId===p.townshipId));checks++;
        rows.push(snapshot.docs.map(d=>d.data()));
      }
      const other=account.uid==='elder_demo'?'helper_demo':'elder_demo';
      await assert.rejects(read(`wallets/${other}`),{code:'permission-denied'});checks++;
      if (defaults) {
        assert.equal(wallet.balance,0);assert.equal(rows[0].length,0);assert.equal(rows[1].length,0);
        assert(rows[2].every(c=>c.status==='pending_policy'&&c.amountCoins===null&&c.ledgerEntryId===null));checks++;
        if(account.uid==='elder_demo'){assert(rows[2].length>0,'Verify the main elder attendance in the browser first');checks++;}
      }
    } else if(p.role==='family') {
      await assert.rejects(read('wallets/elder_demo'),{code:'permission-denied'});checks++;
      for(const [path,owner,time] of [['wallets/elder_demo/entries','ownerUid','createdAt'],['redemptions','ownerUid','issuedAt'],['rewardClaims','beneficiaryUid','verifiedAt']]) {
        await assert.rejects(getDocsFromServer(query(collection(db,path),where(owner,'==','elder_demo'),where('townshipId','==',p.townshipId),orderBy(time,'desc'))),{code:'permission-denied'});checks++;
      }
    } else {
      assert.equal((await read('wallets/elder_demo')).data().townshipId,p.townshipId);checks++;
    }
    console.log(`PASS ${account.email}: wallet query and privacy boundaries`);
  } finally {await terminate(db);await deleteApp(app);}
}
console.log(`Passed ${checks} read-only wallet checks${defaults?', including pending-only rewards and zero balances/transactions/redemptions':''}.`);
