// Authenticated, read-only local integration checks. Never resets or seeds data.
import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,getDocsFromServer,getDocFromServer,collection,doc,query,where,orderBy,terminate} from 'firebase/firestore';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {localEnvironment,projectId,region} from '../../scripts/local.mjs';
import {demoAccounts,demoPassword} from '../../scripts/fixtures.mjs';

localEnvironment();
let checks=0;
for (const account of demoAccounts) {
  const app=initializeApp({apiKey:'local-demo-key',projectId,appId:'1:1234567890:web:coordination-check'},`coordination-read-${account.uid}`);
  const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
  const db=getFirestore(app);connectFirestoreEmulator(db,'127.0.0.1',8080);
  const functions=getFunctions(app,region);connectFunctionsEmulator(functions,'127.0.0.1',5001);
  const rows=(path,...filters)=>getDocsFromServer(query(collection(db,path),...filters));
  const call=async(name,fields={})=>{
    const result=(await httpsCallable(functions,name,{timeout:120000})({contractVersion:1,...fields})).data;
    assert.equal(result.contractVersion,1);checks++;return result.data;
  };
  const progress=(scope,entityId)=>call('getProgress',{scope,entityId,periodType:'week',periodKey:null});
  try {
    await signInWithEmailAndPassword(auth,account.email,demoPassword);
    const p={...(await getDocFromServer(doc(db,`users/${account.uid}`))).data(),uid:account.uid};
    const availability=(await call('getAvailabilitySummary')).availabilitySummary;
    assert.equal(availability.townshipId,p.townshipId);assert.equal(availability.isDemo,true);
    assert(availability.cells.every(c=>c.suppressed ? c.helperCount===null&&c.requestCount===null : Number.isInteger(c.helperCount)&&c.helperCount>=5));
    assert(availability.cells.every(c=>!('helperIds' in c)&&!('requestIds' in c)));checks++;
    for(const path of ['availabilityDemoInputs','progressTargets','demoProgressHistory']) {
      await assert.rejects(rows(path),{code:'permission-denied'});checks++;
    }
    if(p.householdId){assert.equal((await progress('household',p.householdId)).progress.entityId,p.householdId);checks++;}
    let requests=[];
    if(p.role==='coordinator') {
      assert.equal((await call('getCoordinatorSummary')).summary.townshipId,p.townshipId);
      assert.equal((await progress('township',p.townshipId)).progress.latestOuting,null);
      const elders=await rows('users',where('townshipId','==',p.townshipId),where('role','==','elder'));
      assert(elders.size>=2);checks++;
      await rows('reports',where('townshipId','==',p.townshipId),orderBy('createdAt','desc'));checks++;
      await rows('helperBlocks',where('townshipId','==',p.townshipId));checks++;
    } else {
      await assert.rejects(call('getCoordinatorSummary'),{code:'functions/permission-denied'});checks++;
      await assert.rejects(progress('township',p.townshipId),e=>e.code==='functions/failed-precondition'&&e.details?.reason==='SUMMARY_SUPPRESSED');checks++;
      await rows('reports',where('townshipId','==',p.townshipId),where('createdBy','==',p.uid),where('elderId','==',null),orderBy('createdAt','desc'));checks++;
      console.log(`PASS ${p.uid}: unlinked report query`);
      if(p.role==='elder') {
        requests=(await rows('requests',where('elderId','==',p.uid),orderBy('startsAt','desc'))).docs.map(d=>({id:d.id,...d.data()}));
        await rows('helperBlocks',where('townshipId','==',p.townshipId),where('elderId','==',p.uid));checks++;
      } else if(p.role==='helper') {
        requests=(await rows('requests',where('townshipId','==',p.townshipId),where('helperId','==',p.uid),orderBy('startsAt'))).docs.map(d=>({id:d.id,...d.data()}));
        assert((await progress('helper',p.uid)).progress.counts.helpingSessions>=0);checks++;
      } else if(p.uid==='family_demo') {
        requests=(await rows('requests',where('elderId','==','elder_demo'),where('householdId','==',p.householdId),orderBy('startsAt','desc'))).docs.map(d=>({id:d.id,...d.data()}));
      }
      for(const r of requests) {
        await rows('reports',where('townshipId','==',p.townshipId),where('createdBy','==',p.uid),where('requestId','==',r.id),where('elderId','==',r.elderId),where('householdId','==',r.householdId),orderBy('createdAt','desc'));checks++;
      }
    }
    const elderIds=p.role==='coordinator'?['elder_demo','elder_solo']:p.role==='elder'?[p.uid]:p.role==='helper'?[...new Set(requests.map(r=>r.elderId))]:['elder_demo'];
    for(const elderId of elderIds) {
      for(const scope of p.role==='family'?['daily_sharing','family_booking']:['none']) {
        const read=rows('notifications',where('recipientUid','==',p.uid),where('elderId','==',elderId),where('consentScope','==',scope),orderBy('createdAt','desc'));
        if(p.uid==='family_unrelated') await assert.rejects(read,{code:'permission-denied'});
        else assert((await read).docs.every(d=>d.data().recipientUid===p.uid&&d.data().consentScope===scope));
        checks++;
      }
    }
    if(p.role==='elder'||p.uid==='family_demo'||p.role==='coordinator') {
      const e=p.role==='elder'?p.uid:'elder_demo';
      const pr=(await progress('elder',e)).progress;
      assert.equal(pr.entityId,e);assert.equal(pr.targets.outings,2);
      if(pr.latestOuting) assert.deepEqual(Object.keys(pr.latestOuting).sort(),['activityTitle','attendanceId','completedAt','participationId','requestId'].sort());checks++;
      await rows('cheers',where('elderId','==',e),orderBy('createdAt','desc'));checks++;
    } else {
      await assert.rejects(progress('elder','elder_demo'),{code:'functions/permission-denied'});checks++;
      await assert.rejects(rows('cheers',where('elderId','==','elder_demo'),orderBy('createdAt','desc')),{code:'permission-denied'});checks++;
    }
    console.log(`PASS ${account.email}: exact scoped queries, summaries and privacy`);
  } finally {await terminate(db);await deleteApp(app);}
}
console.log(`Passed ${checks} read-only Stage 6 checks; no saved demo data was changed.`);
