// Read-only client verification. Does not seed, reset or write domain data.
// Optional --expect-browser-results checks the documented elder-verify / solo-reject walkthrough.
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,getDocsFromServer,getDocFromServer,collection,doc,query,where,orderBy,terminate} from 'firebase/firestore';
import {localEnvironment,projectId} from '../../scripts/local.mjs';
import {demoAccounts,demoPassword} from '../../scripts/fixtures.mjs';

localEnvironment();
const expectBrowser = process.argv.includes('--expect-browser-results');
let checks = 0;
let elderAttendance, elderParticipation;
const accounts = [...demoAccounts].sort((a,b) => (a.uid === 'elder_demo' ? -1 : b.uid === 'elder_demo' ? 1 : 0));
for (const account of accounts) {
  const app = initializeApp({apiKey:'local-demo-key',projectId,appId:'1:1234567890:web:emascare-demo'},`attendance-read-${account.uid}`);
  const auth = getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  const db = getFirestore(app); connectFirestoreEmulator(db,'127.0.0.1',8080);
  const read = path => getDocFromServer(doc(db,path));
  try {
    await signInWithEmailAndPassword(auth,account.email,demoPassword);
    const p = (await read(`users/${account.uid}`)).data();
    assert.equal(p.role,account.role); checks++;
    await assert.rejects(getDocsFromServer(collection(db,'activityAttendances')),{code:'permission-denied'}); checks++;
    let rows = [];
    if (p.role === 'elder') {
      const snapshot = await getDocsFromServer(query(collection(db,'activityAttendances'),where('elderId','==',account.uid),orderBy('createdAt','desc')));
      rows = snapshot.docs.map(d=>({id:d.id,...d.data()}));
      assert(rows.every(r=>r.elderId === account.uid)); checks++;
      const past = rows.find(r=>r.activityId === 'activity_demo_attendance');
      if (account.uid === 'elder_demo') { elderAttendance=past?.id; elderParticipation=past?.participationId; }
      if (expectBrowser) {
        assert(past,'The browser walkthrough must save attendance for both demo elders');
        assert.equal(past.status,account.uid === 'elder_demo' ? 'verified' : 'rejected');
        assert.equal(past.mode,'standalone');
        assert(past.submittedAt?.toDate());
        assert(past.reviewedAt?.toDate());
        assert.equal(past.reviewedBy,'coordinator_demo');
        assert(past.reviewNote?.trim()); checks++;
        if (past.status === 'verified') {
          assert(past.verifiedAt?.toDate()); assert(past.completionEventId); assert(past.participationId);
          const claim = (await read(`rewardClaims/${past.participationId}`)).data();
          assert.equal(claim.status,'pending_policy'); assert.equal(claim.amountCoins,null); assert.equal(claim.ledgerEntryId,null);
          const wallet = (await read(`wallets/${account.uid}`)).data(); assert.equal(wallet.balance,0);
          const ledger = await getDocsFromServer(query(collection(db,`wallets/${account.uid}/entries`),where('ownerUid','==',account.uid),where('townshipId','==',p.townshipId)));
          assert.equal(ledger.size,0); checks++;
        } else {
          assert.equal(past.verifiedAt,null); assert.equal(past.participationId,null); assert.equal(past.completionEventId,null); assert.equal(past.verificationMethod,null); checks++;
        }
      }
    } else if (p.role === 'family') {
      const household = (await read(`households/${p.householdId}`)).data();
      if (household?.elderIds.includes('elder_demo')) {
        const request = getDocsFromServer(query(collection(db,'activityAttendances'),where('elderId','==','elder_demo'),where('householdId','==',p.householdId),orderBy('createdAt','desc')));
        if (household.elderAccess.elder_demo.familySharingEnabled) {
          const records = await request;
          assert(records.docs.every(d=>d.data().elderId === 'elder_demo' && d.data().householdId === p.householdId));
          if (expectBrowser) assert(records.docs.some(d=>d.id === elderAttendance));
        } else { await assert.rejects(request,{code:'permission-denied'}); }
        checks++;
      } else if (elderAttendance) { await assert.rejects(read(`activityAttendances/${elderAttendance}`),{code:'permission-denied'}); checks++; }
      if (elderParticipation) { await assert.rejects(read(`rewardClaims/${elderParticipation}`),{code:'permission-denied'}); checks++; }
      await assert.rejects(read('wallets/elder_demo'),{code:'permission-denied'}); checks++;
    } else if (p.role === 'coordinator') {
      const records = await getDocsFromServer(query(collection(db,'activityAttendances'),where('townshipId','==',p.townshipId),where('status','==','submitted'),orderBy('submittedAt')));
      assert(records.docs.every(d=>d.data().townshipId === p.townshipId && d.data().status === 'submitted'));
      if (expectBrowser) assert(!records.docs.some(d=>['elder_demo','elder_solo'].includes(d.data().elderId) && d.data().activityId === 'activity_demo_attendance'));
      checks++;
    } else if (elderAttendance) { await assert.rejects(read(`activityAttendances/${elderAttendance}`),{code:'permission-denied'}); checks++; }
    console.log(`PASS ${account.email}: scoped attendance reads and permission boundaries`);
  } finally { await terminate(db); await deleteApp(app); }
}
console.log(`Passed ${checks} read-only attendance checks${expectBrowser ? ', including saved browser verification/rejection and unchanged coins' : ''}.`);
