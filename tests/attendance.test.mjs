import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {getFirestore,connectFirestoreEmulator,doc,getDocFromServer,getDocsFromServer,collection,query,where,orderBy,setDoc,terminate} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp as deleteAdminApp} from 'firebase-admin/app';
import {demoClients,seedDemo,resetDemo} from '../scripts/demo.mjs';
import {demoAccounts,demoPassword,townshipId} from '../scripts/fixtures.mjs';
import {projectId,region} from '../scripts/local.mjs';

const require=createRequire(import.meta.url);
const {createAttendanceService}=require('../functions/lib/attendance.js');
const {createSessionService}=require('../functions/lib/sessions.js');
const {attendanceId,activityLockId,completionId,participationId}=require('../functions/lib/completions.js');
const {wireRecord}=require('../functions/lib/scheduling.js');
const command=(fields={})=>({contractVersion:1,idempotencyKey:crypto.randomUUID(),...fields});
const reason=(expected)=>(error)=>error.details?.reason===expected;
const past='activity_demo_attendance';
const submitInput=(activityId=past)=>command({activityId});
const reviewInput=(id,extra={})=>command({attendanceId:id,decision:'verify',verificationMethod:'organizer_roster',note:'Matched the organizer attendance roster.',...extra});

test('Stage 4 standalone attendance, trusted verification and shared completion identity', {timeout:240000}, async(t)=>{
  const admin=await demoClients(),{db}=admin,clients=new Map();
  try {
    await resetDemo(admin); await seedDemo(admin);
    for(const account of demoAccounts){
      const app=initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:demo'},crypto.randomUUID());
      const auth=getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const firestore=getFirestore(app); connectFirestoreEmulator(firestore,'127.0.0.1',8080);
      const functions=getFunctions(app,region); connectFunctionsEmulator(functions,'127.0.0.1',5001);
      await signInWithEmailAndPassword(auth,account.email,demoPassword);
      clients.set(account.uid,{app,firestore,functions});
    }
    const call=async(uid,name,input)=>(await httpsCallable(clients.get(uid).functions,name)(input)).data;
    const stored=async(path)=>(await db.doc(path).get()).data();
    const read=(uid,path)=>getDocFromServer(doc(clients.get(uid).firestore,path));
    const submit=async(uid='elder_demo',activityId=past)=>(await call(uid,'submitActivityAttendance',submitInput(activityId))).data.attendance;
    const review=(id,extra={})=>call('coordinator_demo','reviewActivityAttendance',reviewInput(id,extra));
    const effectCounts=async()=>Promise.all(['completionEvents','participations','rewardClaims','completionMarkers'].map(async(name)=>(await db.collection(name).get()).size));
    const futureInput=async()=>{
      const a=await stored('activities/activity_garden');
      return command({elderId:'elder_demo',activityId:'activity_garden',placeId:a.placeId,startsAt:a.startsAt.toDate().toISOString(),
        endsAt:a.endsAt.toDate().toISOString(),taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'any'});
    };
    t.beforeEach(async()=>{await resetDemo(admin);await seedDemo(admin);});

    await t.test('only actual elders submit and only current same-township coordinators review',async()=>{
      const app=initializeApp({projectId,apiKey:'local-demo-key'},crypto.randomUUID());
      try{
        const functions=getFunctions(app,region);connectFunctionsEmulator(functions,'127.0.0.1',5001);
        for(const [name,input] of [['submitActivityAttendance',submitInput()],['reviewActivityAttendance',reviewInput('missing')]]){
          await assert.rejects(httpsCallable(functions,name)(input),reason('AUTH_REQUIRED'));
        }
      }finally{await deleteApp(app);}
      for(const uid of ['family_demo','family_unrelated','helper_demo','coordinator_demo'])await assert.rejects(call(uid,'submitActivityAttendance',submitInput()),reason('ROLE_NOT_ALLOWED'));
      const attendance=await submit('elder_solo');
      for(const uid of ['elder_demo','elder_solo','family_demo','helper_demo'])await assert.rejects(call(uid,'reviewActivityAttendance',reviewInput(attendance.id)),reason('ROLE_NOT_ALLOWED'));
      await db.doc('users/coordinator_demo').update({townshipId:'other'});
      await assert.rejects(review(attendance.id),reason('TOWNSHIP_NOT_ALLOWED'));
      assert.equal((await stored(`activityAttendances/${attendance.id}`)).status,'submitted');
      assert.deepEqual(await effectCounts(),[0,0,0,0]);
    });

    await t.test('standalone elder submission creates one unverified record across different retry keys and awards nothing',async()=>{
      const input=submitInput();
      const results=await Promise.all([call('elder_solo','submitActivityAttendance',input),call('elder_solo','submitActivityAttendance',input)]);
      assert.deepEqual(results[0],results[1]);
      const attendance=results[0].data.attendance,id=attendanceId(past,'elder_solo');
      assert.deepEqual(results[0],{contractVersion:1,data:{attendance:wireRecord(id,await stored(`activityAttendances/${id}`))}});
      assert.equal(attendance.mode,'standalone');assert.equal(attendance.status,'submitted');assert.equal(attendance.linkedRequestId,null);
      for(const field of ['verifiedAt','verificationMethod','reviewedBy','reviewedAt','reviewNote','completionEventId','participationId'])assert.equal(attendance[field],null);
      assert.deepEqual(await submit('elder_solo'),attendance);
      assert.deepEqual(await effectCounts(),[0,0,0,0]);
      assert.equal((await stored('wallets/elder_solo')).balance,0);
      await assert.rejects(call('elder_solo','submitActivityAttendance',{...input,activityId:'activity_hall'}),reason('IDEMPOTENCY_KEY_REUSED'));
    });

    await t.test('trusted coordinator verification produces one elder participation, pending-policy claim and outing marker atomically',async()=>{
      const attendance=await submit('elder_solo'),input=reviewInput(attendance.id,{verificationMethod:'coordinator_observed',note:'Observed the elder attending in person.'});
      const results=await Promise.all([call('coordinator_demo','reviewActivityAttendance',input),call('coordinator_demo','reviewActivityAttendance',input)]);
      assert.deepEqual(results[0],results[1]);
      const verified=results[0].data.attendance,eventId=completionId(past,attendance.id),pid=participationId(eventId,'elder_solo');
      assert.equal(verified.status,'verified');assert.equal(verified.submittedAt,attendance.submittedAt);
      assert.equal(verified.reviewedBy,'coordinator_demo');assert.equal(verified.verifiedAt,verified.reviewedAt);
      assert.equal(verified.participationId,pid);assert.equal(verified.completionEventId,eventId);
      assert.deepEqual(await effectCounts(),[1,1,1,1]);
      const participation=await stored(`participations/${pid}`),claim=await stored(`rewardClaims/${pid}`);
      assert.deepEqual(participation.sourceRequestIds,[]);assert.equal(participation.attendanceId,attendance.id);
      assert.equal(participation.beneficiaryRole,'elder');assert.equal(participation.outingClassification,'counts');
      assert.equal(claim.status,'pending_policy');assert.equal(claim.reason,'REWARD_POLICY_PENDING');
      for(const field of ['eligible','amountCoins','rateCoins','ruleId','ruleVersion','ledgerEntryId'])assert.equal(claim[field],null);
      assert.equal((await stored('wallets/elder_solo')).balance,0);
      assert.equal((await db.collection('wallets/elder_solo/entries').get()).size,0);
      assert.equal((await stored(`activityElderLocks/${activityLockId(past,'elder_solo')}`)).state,'completed');
      assert.deepEqual(await submit('elder_solo'),verified);
      await assert.rejects(review(attendance.id),reason('ATTENDANCE_ALREADY_REVIEWED'));
      await assert.rejects(review(attendance.id,{decision:'reject',verificationMethod:null,note:'Conflicting review.'}),reason('ATTENDANCE_ALREADY_REVIEWED'));
      await assert.rejects(call('coordinator_demo','reviewActivityAttendance',{...input,note:'Changed evidence under the same key.'}),reason('IDEMPOTENCY_KEY_REUSED'));
    });

    await t.test('rejection is terminal, needs a note and null method, and gives no completion, reward or progress',async()=>{
      const attendance=await submit(),input=reviewInput(attendance.id,{decision:'reject',verificationMethod:null,note:'Attendance could not be confirmed against the roster.'});
      const result=await call('coordinator_demo','reviewActivityAttendance',input);
      assert.equal(result.data.attendance.status,'rejected');assert.equal(result.data.attendance.verifiedAt,null);
      assert.equal(result.data.attendance.completionEventId,null);assert.equal(result.data.attendance.participationId,null);
      assert.equal(result.data.attendance.reviewNote,input.note);
      assert.deepEqual(await effectCounts(),[0,0,0,0]);
      assert.deepEqual(await call('coordinator_demo','reviewActivityAttendance',input),result);
      assert.deepEqual(await submit(),result.data.attendance);
      await assert.rejects(review(attendance.id),reason('ATTENDANCE_ALREADY_REVIEWED'));
    });

    await t.test('different-key verify/reject races have one terminal outcome and at most one set of completion effects',async()=>{
      const attendance=await submit();
      const results=await Promise.allSettled([review(attendance.id),review(attendance.id,{decision:'reject',verificationMethod:null,note:'No reliable attendance evidence.'})]);
      assert.equal(results.filter((r)=>r.status==='fulfilled').length,1);
      assert.equal(results.find((r)=>r.status==='rejected').reason.details.reason,'ATTENDANCE_ALREADY_REVIEWED');
      const current=await stored(`activityAttendances/${attendance.id}`),expected=current.status==='verified'?1:0;
      assert.deepEqual(await effectCounts(),[expected,expected,expected,expected]);
    });

    await t.test('activity timing, participation mode and current authority/source links are rechecked before verification',async()=>{
      const a=await stored('activities/activity_garden');
      let now=Timestamp.fromMillis(a.endsAt.toMillis()-1);const service=createAttendanceService(db,()=>now);
      await assert.rejects(service.submitActivityAttendance('elder_demo',submitInput('activity_garden')),reason('ACTIVITY_NOT_FINISHED'));
      now=a.endsAt;const submitted=await service.submitActivityAttendance('elder_demo',submitInput('activity_garden'));
      now=Timestamp.fromMillis(a.endsAt.toMillis()-1);
      await assert.rejects(service.reviewActivityAttendance('coordinator_demo',reviewInput(submitted.data.attendance.id)),reason('ACTIVITY_NOT_FINISHED'));
      await db.doc('activities/activity_garden').update({participationMode:'online'});
      now=a.endsAt;await assert.rejects(service.reviewActivityAttendance('coordinator_demo',reviewInput(submitted.data.attendance.id)),reason('ACTIVITY_NOT_IN_PERSON'));
      await db.doc('activities/activity_garden').update({participationMode:'in_person',endsAt:a.startsAt});
      await assert.rejects(service.reviewActivityAttendance('coordinator_demo',reviewInput(submitted.data.attendance.id)),reason('INVALID_ACTIVITY_SCHEDULE'));
      await db.doc('activities/activity_garden').set(a);
      const input=reviewInput(submitted.data.attendance.id);
      const verified=await service.reviewActivityAttendance('coordinator_demo',input);
      await db.doc('users/coordinator_demo').update({role:'helper'});
      await assert.rejects(service.reviewActivityAttendance('coordinator_demo',input),reason('ROLE_NOT_ALLOWED'));
      await db.doc('users/coordinator_demo').update({role:'coordinator'});
      await db.doc('users/elder_demo').update({householdId:'household_solo'});
      await assert.rejects(service.reviewActivityAttendance('coordinator_demo',input),reason('UNRELATED_HOUSEHOLD'));
      await db.doc('users/elder_demo').update({householdId:'household_demo'});
      await db.doc('activities/activity_garden').update({townshipId:'other'});
      await assert.rejects(service.reviewActivityAttendance('coordinator_demo',input),reason('TOWNSHIP_NOT_ALLOWED'));
      await db.doc('activities/activity_garden').set(a);
      assert.deepEqual(await service.reviewActivityAttendance('coordinator_demo',input),verified);
      await assert.rejects(review('unknown'),reason('ATTENDANCE_NOT_FOUND'));
      const bad=db.doc('activityAttendances/stage4_bad_link');
      try{await bad.set(await stored(`activityAttendances/${submitted.data.attendance.id}`));await assert.rejects(review('stage4_bad_link'),reason('INVALID_ATTENDANCE_LINK'));}
      finally{await bad.delete();}
    });

    await t.test('every active companion state blocks standalone bypass; completed sessions return existing attendance unchanged',async()=>{
      const input=await futureInput(),a=await stored('activities/activity_garden');
      let now=Timestamp.now();const sessions=createSessionService(db,()=>now);
      const attendance=createAttendanceService(db,()=>a.endsAt);
      const r=(await sessions.createRequest('elder_demo',input)).data.request;
      const bypass=()=>assert.rejects(attendance.submitActivityAttendance('elder_demo',submitInput('activity_garden')),reason('ATTENDANCE_MANAGED_BY_SESSION'));
      const act=(uid,action)=>sessions.transitionRequest(uid,command({requestId:r.id,action}));
      await bypass();await sessions.assignRequest('coordinator_demo',command({requestId:r.id,pairingId:'pairing_demo'}));
      await bypass();await act('helper_demo','accept');await bypass();
      now=a.startsAt;await act('helper_demo','start');await bypass();
      now=a.endsAt;await act('helper_demo','finish');await bypass();
      await act('elder_demo','confirm');await bypass();
      assert.equal((await db.collection('activityAttendances').get()).size,0);
      await act('helper_demo','confirm');
      const before=await stored(`activityAttendances/${attendanceId('activity_garden','elder_demo')}`),counts=await effectCounts();
      assert.equal(before.verificationMethod,'mutual_session_confirmation');
      assert.deepEqual((await attendance.submitActivityAttendance('elder_demo',submitInput('activity_garden'))).data.attendance,wireRecord(attendanceId('activity_garden','elder_demo'),before));
      assert.deepEqual((await attendance.reviewActivityAttendance('coordinator_demo',reviewInput(attendanceId('activity_garden','elder_demo')))).data.attendance,wireRecord(attendanceId('activity_garden','elder_demo'),before));
      assert.deepEqual(await effectCounts(),counts);assert.deepEqual(counts,[1,2,2,2]);
      await assert.rejects(attendance.reviewActivityAttendance('coordinator_demo',reviewInput(attendanceId('activity_garden','elder_demo'),{decision:'reject',verificationMethod:null,note:'Cannot reverse a completed session.'})),reason('ATTENDANCE_ALREADY_REVIEWED'));
    });

    await t.test('cancellation permits standalone attendance; review rechecks a newly governing request lock',async()=>{
      const input=await futureInput(),a=await stored('activities/activity_garden'),sessions=createSessionService(db);
      const r=(await sessions.createRequest('elder_demo',input)).data.request;
      await sessions.transitionRequest('elder_demo',command({requestId:r.id,action:'cancel'}));
      const attendance=createAttendanceService(db,()=>a.endsAt);
      const submitted=(await attendance.submitActivityAttendance('elder_demo',submitInput('activity_garden'))).data.attendance;
      const lockRef=db.doc(`activityElderLocks/${activityLockId('activity_garden','elder_demo')}`),lock=await stored(lockRef.path);
      // Simulate a conflicting source discovered at review; clients cannot write it.
      await db.doc(`requests/${r.id}`).update({state:'awaiting_confirmation'});
      await lockRef.set({...lock,requestId:r.id,state:'active'});
      await assert.rejects(attendance.reviewActivityAttendance('coordinator_demo',reviewInput(submitted.id)),reason('ATTENDANCE_MANAGED_BY_SESSION'));
      assert.equal((await stored(`activityAttendances/${submitted.id}`)).status,'submitted');
      assert.deepEqual(await effectCounts(),[0,0,0,0]);
      await db.doc(`requests/${r.id}`).update({state:'cancelled'});await lockRef.set(lock);
      assert.equal((await attendance.reviewActivityAttendance('coordinator_demo',reviewInput(submitted.id))).data.attendance.status,'verified');
    });

    await t.test('request and attendance races contend on the same activity/elder lock',async()=>{
      const a=await stored('activities/activity_garden'),input=await futureInput();
      // Deliberately straddle the activity boundary to exercise both writers'
      // lock logic even with clock skew. No client clock override exists.
      const requests=createSessionService(db,()=>Timestamp.fromMillis(a.startsAt.toMillis()-1));
      const attendance=createAttendanceService(db,()=>a.endsAt);
      const results=await Promise.allSettled([requests.createRequest('elder_demo',input),attendance.submitActivityAttendance('elder_demo',submitInput('activity_garden'))]);
      assert.equal(results.filter((r)=>r.status==='fulfilled').length,1);
      assert.ok(['ATTENDANCE_ALREADY_SUBMITTED','ATTENDANCE_MANAGED_BY_SESSION'].includes(results.find((r)=>r.status==='rejected').reason.details.reason));
      assert.deepEqual(await effectCounts(),[0,0,0,0]);
    });

    await t.test('distinct elders at one occurrence share one event and retain separate participation identities',async()=>{
      const a=await submit('elder_demo'),b=await submit('elder_solo');
      await review(a.id);await review(b.id);
      const eventId=completionId(past,a.id),event=await stored(`completionEvents/${eventId}`);
      assert.deepEqual(await effectCounts(),[1,2,2,2]);
      for(const uid of ['elder_demo','elder_solo'])assert.equal((await stored(`participations/${participationId(eventId,uid)}`)).beneficiaryUid,uid);
      const firstTime=event.firstVerifiedAt.toMillis();
      await submit('elder_demo');assert.equal((await stored(`completionEvents/${eventId}`)).firstVerifiedAt.toMillis(),firstTime);
    });

    await t.test('elder/family history and coordinator queues are scoped; consent does not grant financial or mutation access',async()=>{
      const attendance=await submit(),fs=(uid)=>clients.get(uid).firestore;
      for(const [uid,filters] of [
        ['elder_demo',[where('elderId','==','elder_demo'),orderBy('createdAt','desc')]],
        ['family_demo',[where('elderId','==','elder_demo'),where('householdId','==','household_demo'),orderBy('createdAt','desc')]],
        ['coordinator_demo',[where('townshipId','==',townshipId),where('status','==','submitted'),orderBy('submittedAt')]],
      ]){
        assert.equal((await getDocsFromServer(query(collection(fs(uid),'activityAttendances'),...filters))).size,1);
        await assert.rejects(getDocsFromServer(collection(fs(uid),'activityAttendances')),{code:'permission-denied'});
      }
      for(const uid of ['helper_demo','elder_solo','family_unrelated'])await assert.rejects(read(uid,`activityAttendances/${attendance.id}`),{code:'permission-denied'});
      await db.doc('elderSettings/elder_demo').update({familyBookingEnabled:false});await read('family_demo',`activityAttendances/${attendance.id}`);
      await db.doc('elderSettings/elder_demo').update({familyBookingEnabled:true,familySharingEnabled:false});
      await assert.rejects(read('family_demo',`activityAttendances/${attendance.id}`),{code:'permission-denied'});
      const done=(await review(attendance.id)).data.attendance;
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:true});await read('family_demo',`activityAttendances/${attendance.id}`);
      for(const name of ['participations','rewardClaims']){
        for(const uid of ['elder_demo','coordinator_demo'])await read(uid,`${name}/${done.participationId}`);
        for(const uid of ['family_demo','helper_demo'])await assert.rejects(read(uid,`${name}/${done.participationId}`),{code:'permission-denied'});
      }
      for(const uid of ['elder_demo','family_demo','coordinator_demo'])await assert.rejects(setDoc(doc(fs(uid),`activityAttendances/${attendance.id}`),{status:'verified'}),{code:'permission-denied'});
    });

    await t.test('shared completion preserves existing verification and claim when evidence converges',async()=>{
      const attendance=await submit(),eventId=completionId(past,attendance.id),pid=participationId(eventId,'elder_demo');
      const at=Timestamp.fromMillis(Date.now()-1000),claim={participationId:pid,completionEventId:eventId,beneficiaryUid:'elder_demo',townshipId,status:'pending_policy',amountCoins:null,verifiedAt:at};
      await db.doc(`completionEvents/${eventId}`).set({townshipId,firstVerifiedAt:at});
      await db.doc(`participations/${pid}`).set({completionEventId:eventId,beneficiaryUid:'elder_demo',beneficiaryRole:'elder',townshipId,sourceRequestIds:['existing_evidence_request'],verifiedAt:at,createdAt:at});
      await db.doc(`rewardClaims/${pid}`).set(claim);
      await review(attendance.id);
      assert.deepEqual(await stored(`rewardClaims/${pid}`),claim);
      const participant=await stored(`participations/${pid}`);
      assert.equal(participant.verifiedAt.toMillis(),at.toMillis());assert.deepEqual(participant.sourceRequestIds,['existing_evidence_request']);
      assert.deepEqual(await effectCounts(),[1,1,1,1]);
    });

    await t.test('handover JSON matches exact callable service response shapes for submission, verification and rejection',async()=>{
      const fixtures=JSON.parse(await readFile(new URL('../docs/fixtures/stage4_attendance.json',import.meta.url),'utf8'));
      let now=Timestamp.fromDate(new Date(fixtures.serverTime));
      await resetDemo(admin);await seedDemo(admin,now.toDate());const service=createAttendanceService(db,()=>now);
      for(const name of ['submit','verify','submitForRejection','reject']){
        const example=fixtures[name];now=Timestamp.fromDate(new Date(example.at));
        assert.deepEqual(await service[example.functionName](example.callerUid,example.input),example.output);
      }
      const claim=fixtures.pendingClaim;assert.deepEqual(wireRecord(claim.id,await stored(`rewardClaims/${claim.id}`)),claim);
    });

    await t.test('reset removes standalone evidence, receipts and canonical effects while preserving other attendance and shared events',async()=>{
      const a=await submit('elder_solo'),done=(await review(a.id)).data.attendance;
      const externalId=attendanceId(past,'stage4_external'),pid=participationId(done.completionEventId,'stage4_external');
      const externalRef=db.doc(`activityAttendances/${externalId}`),participantRef=db.doc(`participations/${pid}`);
      try{
        await externalRef.set({...await stored(`activityAttendances/${a.id}`),elderId:'stage4_external',householdId:'external',participationId:pid});
        await participantRef.set({completionEventId:done.completionEventId,beneficiaryUid:'stage4_external',townshipId,sourceRequestIds:[],attendanceId:externalId});
        await resetDemo(admin);
        for(const path of [`activityAttendances/${a.id}`,`participations/${done.participationId}`,`rewardClaims/${done.participationId}`,`completionMarkers/${done.participationId}`,`activityElderLocks/${activityLockId(past,'elder_solo')}`])assert.equal(await stored(path),undefined);
        assert.ok(await stored(externalRef.path));assert.ok(await stored(participantRef.path));assert.ok(await stored(`completionEvents/${done.completionEventId}`));
        assert.equal((await db.collection('commandReceipts').where('functionName','==','submitActivityAttendance').get()).size,0);
        assert.equal((await db.collection('commandReceipts').where('functionName','==','reviewActivityAttendance').get()).size,0);
      }finally{await externalRef.delete();await participantRef.delete();await db.doc(`completionEvents/${done.completionEventId}`).delete();}
      await seedDemo(admin);const own=await submit();const verified=(await review(own.id)).data.attendance;
      await resetDemo(admin);assert.equal(await stored(`completionEvents/${verified.completionEventId}`),undefined);
    });
  }finally{
    for(const{app,firestore}of clients.values()){await terminate(firestore);await deleteApp(app);}
    await resetDemo(admin);await seedDemo(admin);await db.terminate();await deleteAdminApp(admin.app);
  }
});
