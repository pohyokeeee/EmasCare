import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {getFirestore,connectFirestoreEmulator,doc,getDocFromServer,setDoc,terminate,collection,query,where,orderBy,getDocsFromServer} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp as deleteAdminApp} from 'firebase-admin/app';
import {demoClients,resetDemo,seedDemo} from '../scripts/demo.mjs';
import {demoAccounts,demoPassword,townshipId} from '../scripts/fixtures.mjs';
import {projectId,region} from '../scripts/local.mjs';
const require=createRequire(import.meta.url);
const {createOperationsService}=require('../functions/lib/operations.js');
const {createCheckInService,malaysiaDate}=require('../functions/lib/checkins.js');
const {createNotificationService}=require('../functions/lib/notifications.js');
const {createSummaryService}=require('../functions/lib/summaries.js');
const {createVoiceService}=require('../functions/lib/voice.js');
const {createAttendanceService}=require('../functions/lib/attendance.js');
const {helperBlockId}=require('../functions/lib/sessions.js');
const cmd=(fields={})=>({contractVersion:1,idempotencyKey:crypto.randomUUID(),...fields});
const reason=(r)=>(e)=>e.details?.reason===r;
const ts=(s)=>Timestamp.fromDate(new Date(s));

test('Stage 6 coordination, consent-safe notifications, progress and voice boundary', {timeout:600000},async(t)=>{
  const admin=await demoClients(),{db}=admin,clients=new Map();
  try {
    await resetDemo(admin);await seedDemo(admin);
    for(const account of demoAccounts){
      const app=initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:demo'},crypto.randomUUID());
      const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const fs=getFirestore(app);connectFirestoreEmulator(fs,'127.0.0.1',8080);
      const functions=getFunctions(app,region);connectFunctionsEmulator(functions,'127.0.0.1',5001);
      await signInWithEmailAndPassword(auth,account.email,demoPassword);clients.set(account.uid,{app,fs,functions});
    }
    const call=async(uid,name,input)=>(await httpsCallable(clients.get(uid).functions,name)(input)).data;
    const stored=async(path)=>(await db.doc(path).get()).data();
    const read=(uid,path)=>getDocFromServer(doc(clients.get(uid).fs,path));
    const progress=async(uid,scope,entityId,extra={})=>(await call(uid,'getProgress',{contractVersion:1,scope,entityId,periodType:'week',periodKey:null,...extra})).data.progress;
    const submit=async(uid='elder_demo')=>(await call(uid,'submitActivityAttendance',cmd({activityId:'activity_demo_attendance'}))).data.attendance;
    const verify=async(id)=>(await call('coordinator_demo','reviewActivityAttendance',cmd({attendanceId:id,decision:'verify',verificationMethod:'organizer_roster',note:'Matched organizer roster.'}))).data.attendance;
    const complete=async(id='request_demo_ready')=>{
      for(const action of ['accept','start','finish','confirm'])await call('helper_demo','transitionRequest',cmd({requestId:id,action}));
      return (await call('elder_demo','transitionRequest',cmd({requestId:id,action:'confirm'}))).data.request;
    };
    const future=async()=>{
      const a=await stored('activities/activity_garden');return cmd({elderId:'elder_demo',activityId:'activity_garden',placeId:a.placeId,
        startsAt:a.startsAt.toDate().toISOString(),endsAt:a.endsAt.toDate().toISOString(),taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'any'});
    };
    t.beforeEach(async()=>{await resetDemo(admin);await seedDemo(admin);});

    await t.test('all Stage 6 callables enforce Authentication; role checks and disabled live provider work over HTTP',async()=>{
      const app=initializeApp({projectId,apiKey:'local-demo-key'},crypto.randomUUID());
      try{
        const f=getFunctions(app,region);connectFunctionsEmulator(f,'127.0.0.1',5001);
        for(const name of ['setPlaceWarning','submitReport','reviewReport','blockHelper','sendFamilyCheer','markNotificationRead','processDemoDueItems','getProgress','getAvailabilitySummary','getCoordinatorSummary','parseVoiceBooking']){
          await assert.rejects(httpsCallable(f,name)({contractVersion:1}),reason('AUTH_REQUIRED'));
        }
      }finally{await deleteApp(app);}
      await assert.rejects(call('elder_demo','getCoordinatorSummary',{contractVersion:1}),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('family_demo','processDemoDueItems',cmd()),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('elder_demo','parseVoiceBooking',{contractVersion:1,elderId:'elder_demo',locale:'en',input:{type:'text',text:'I want a companion'}}),reason('VOICE_SERVICE_UNAVAILABLE'));
      assert.equal((await db.collection('requests').get()).size,1);
    });
    await t.test('reports have one retry receipt, scoped links, authorized review and a terminal done state',async()=>{
      const input=cmd({kind:'helper_report',requestId:'request_demo_ready',helperId:'helper_demo',placeId:null,text:'Please review the assigned helper.'});
      const results=await Promise.all([call('family_demo','submitReport',input),call('family_demo','submitReport',input)]);assert.deepEqual(results[0],results[1]);
      const r=results[0].data.report;assert.equal(r.state,'new');assert.equal(r.reviewedAt,null);
      await read('family_demo',`reports/${r.id}`);await read('coordinator_demo',`reports/${r.id}`);
      for(const uid of ['family_unrelated','helper_demo','elder_solo'])await assert.rejects(read(uid,`reports/${r.id}`),{code:'permission-denied'});
      await assert.rejects(call('family_unrelated','submitReport',input),reason('UNRELATED_HOUSEHOLD'));
      await assert.rejects(call('elder_demo','reviewReport',cmd({reportId:r.id,state:'seen'})),reason('ROLE_NOT_ALLOWED'));
      const seen=(await call('coordinator_demo','reviewReport',cmd({reportId:r.id,state:'seen'}))).data.report;assert.equal(seen.reviewedBy,'coordinator_demo');
      const doneInput=cmd({reportId:r.id,state:'done'}),done=await call('coordinator_demo','reviewReport',doneInput);
      assert.deepEqual(await call('coordinator_demo','reviewReport',doneInput),done);
      await assert.rejects(call('coordinator_demo','reviewReport',cmd({reportId:r.id,state:'seen'})),reason('INVALID_TRANSITION'));
      await db.doc('elderSettings/elder_demo').update({familyBookingEnabled:false});
      await assert.rejects(call('family_demo','submitReport',input),reason('CONSENT_REQUIRED'));
      await assert.rejects(read('family_demo',`reports/${r.id}`),{code:'permission-denied'});
      const place=(await call('helper_demo','submitReport',cmd({kind:'place_problem',placeId:'place_garden',text:'Wet path.'}))).data.report;
      await read('helper_demo',`reports/${place.id}`);
      await assert.rejects(call('elder_demo','submitReport',cmd({kind:'place_problem',placeId:'place_hall',requestId:'request_demo_ready',text:'x'})),reason('INVALID_REPORT_LINK'));
      await db.doc('users/coordinator_demo').update({townshipId:'other'});
      await assert.rejects(call('coordinator_demo','reviewReport',doneInput),reason('TOWNSHIP_NOT_ALLOWED'));
    });
    await t.test('warnings require same-township coordinator and explicit clearing; expiry means needs review',async()=>{
      let now=ts('2026-10-22T00:00:00Z');const ops=createOperationsService(db,()=>now),summary=createSummaryService(db,()=>now),due=createCheckInService(db,()=>now);
      const input=cmd({placeId:'place_hall',warning:{level:'closed',text:'Access needs review.',expiresAt:'2026-10-22T00:01:00Z'}});
      await assert.rejects(ops.setPlaceWarning('elder_demo',input),reason('ROLE_NOT_ALLOWED'));
      const result=await ops.setPlaceWarning('coordinator_demo',input);assert.equal(result.data.place.liveStatus.level,'closed');
      assert.deepEqual(await ops.setPlaceWarning('coordinator_demo',input),result);
      now=ts('2026-10-22T00:02:00Z');assert.equal((await due.processDemoDueItems('coordinator_demo',cmd())).data.warningsCleared,0);
      assert.equal((await summary.getCoordinatorSummary('coordinator_demo',{contractVersion:1})).data.summary.placeWarnings.needsReview,1);
      assert.ok((await stored('places/place_hall')).liveStatus);
      await assert.rejects(ops.setPlaceWarning('coordinator_demo',cmd({placeId:'place_hall',warning:input.warning})),reason('INVALID_WARNING_EXPIRY'));
      assert.equal((await ops.setPlaceWarning('coordinator_demo',cmd({placeId:'place_hall',warning:null}))).data.place.liveStatus,null);
    });
    await t.test('elder blocking is relation checked and immediately prevents assignment and helper acceptance',async()=>{
      const input=cmd({elderId:'elder_demo',helperId:'helper_demo',reason:'I prefer another companion.'});
      await assert.rejects(call('family_demo','blockHelper',input),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('elder_solo','blockHelper',cmd({...input,elderId:'elder_solo'})),reason('HELPER_RELATION_REQUIRED'));
      assert.deepEqual((await call('elder_demo','blockHelper',input)).data,{elderId:'elder_demo',helperId:'helper_demo',blocked:true});
      const before=await stored(`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`);
      await call('elder_demo','blockHelper',cmd({...input,idempotencyKey:crypto.randomUUID()}));
      assert.deepEqual(await stored(`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`),before);
      await assert.rejects(call('helper_demo','transitionRequest',cmd({requestId:'request_demo_ready',action:'accept'})),reason('HELPER_BLOCKED'));
      const r=(await call('elder_demo','createRequest',await future())).data.request;
      await assert.rejects(call('coordinator_demo','assignRequest',cmd({requestId:r.id,pairingId:'pairing_demo'})),reason('HELPER_BLOCKED'));
      await read('elder_demo',`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`);
      await assert.rejects(read('helper_demo',`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`),{code:'permission-denied'});
    });
    await t.test('due processing materializes server date, deduplicates concurrent alerts and preserves first response',async()=>{
      let now=ts('2026-10-22T01:00:00Z');await resetDemo(admin);await seedDemo(admin,now.toDate());
      const svc=createCheckInService(db,()=>now),notices=createNotificationService(db,()=>now);
      const first=await svc.processDemoDueItems('coordinator_demo',cmd());assert.equal(first.data.remindersCreated,1);assert.equal(first.data.missedAlertsCreated,1);
      const concurrent=await Promise.all([svc.processDemoDueItems('coordinator_demo',cmd()),svc.processDemoDueItems('coordinator_demo',cmd())]);
      for(const result of concurrent)assert.equal(result.data.remindersCreated+result.data.missedAlertsCreated,0);
      now=ts('2026-10-22T01:30:00Z');const missed=await svc.processDemoDueItems('coordinator_demo',cmd());assert.equal(missed.data.missedAlertsCreated,2);
      const familyNotice=(await db.collection('notifications').where('recipientUid','==','family_demo').get()).docs[0];
      await read('family_demo',familyNotice.ref.path);await assert.rejects(read('family_unrelated',familyNotice.ref.path),{code:'permission-denied'});
      const input=cmd({notificationId:familyNotice.id}),readResult=await notices.markNotificationRead('family_demo',input);
      assert.equal(readResult.data.readAt,now.toDate().toISOString());
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      await assert.rejects(read('family_demo',familyNotice.ref.path),{code:'permission-denied'});
      await assert.rejects(notices.markNotificationRead('family_demo',input),reason('CONSENT_REQUIRED'));
      const phone=await svc.recordPhoneResponse('coordinator_demo',cmd({elderId:'elder_demo'}));now=ts('2026-10-22T03:00:00Z');
      const app=await svc.submitCheckIn('elder_demo',cmd());assert.equal(app.data.checkin.source,'coordinator_phone');assert.equal(app.data.checkin.submittedAt,phone.data.checkin.submittedAt);
      assert.equal((await svc.processDemoDueItems('coordinator_demo',cmd())).data.missedAlertsCreated,0);
      assert.equal((await db.collection('notifications').get()).size,4);
      await db.doc('elderSettings/elder_demo').update({pausedOn:'2026-10-23'});
      now=ts('2026-10-23T01:30:00Z');await svc.processDemoDueItems('coordinator_demo',cmd());
      assert.equal((await stored('checkins/elder_demo_2026-10-23')).state,'paused');
      assert.equal((await stored('checkins/elder_solo_2026-10-23')).state,'missed');
    });
    await t.test('booking and sharing notifications remain independent, recipient scoped and free of financial/private fields',async()=>{
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      const r=(await call('elder_demo','createRequest',await future())).data.request;
      await call('coordinator_demo','assignRequest',cmd({requestId:r.id,pairingId:'pairing_demo'}));
      const notices=(await db.collection('notifications').where('recipientUid','==','family_demo').get()).docs;assert.equal(notices.length,2);
      for(const n of notices){assert.equal(n.data().consentScope,'family_booking');await read('family_demo',n.ref.path);assert.deepEqual(Object.keys(n.data().messageParams),['state']);}
      const fs=clients.get('family_demo').fs;
      assert.equal((await getDocsFromServer(query(collection(fs,'notifications'),where('recipientUid','==','family_demo'),where('elderId','==','elder_demo'),where('consentScope','==','family_booking'),orderBy('createdAt','desc')))).size,2);
      await assert.rejects(getDocsFromServer(collection(fs,'notifications')),{code:'permission-denied'});
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:true,familyBookingEnabled:false});
      for(const n of notices)await assert.rejects(read('family_demo',n.ref.path),{code:'permission-denied'});
      const done=await verify((await submit()).id);
      const attendanceNotice=(await db.collection('notifications').where('recipientUid','==','family_demo').where('kind','==','attendance_review').get()).docs[0];
      assert.equal(attendanceNotice.data().consentScope,'daily_sharing');await read('family_demo',attendanceNotice.ref.path);
      assert.equal((await progress('family_demo','elder','elder_demo')).latestOuting.participationId,done.participationId);
    });
    await t.test('verified outings allow one cheer per family across different keys, without extra rewards or progress',async()=>{
      const attendance=await verify((await submit()).id),input=cmd({participationId:attendance.participationId});
      await db.doc('elderSettings/elder_demo').update({familyBookingEnabled:false});
      const results=await Promise.all([call('family_demo','sendFamilyCheer',input),call('family_demo','sendFamilyCheer',cmd({participationId:attendance.participationId}))]);
      assert.deepEqual(results[0],results[1]);assert.equal((await db.collection('cheers').get()).size,1);
      assert.equal((await db.collection('notifications').where('kind','==','family_cheer').get()).size,1);
      assert.equal((await progress('elder_demo','elder','elder_demo')).counts.outings,1);assert.equal((await stored('wallets/elder_demo')).balance,0);
      await read('family_demo',`cheers/${results[0].data.cheer.id}`);await read('elder_demo',`cheers/${results[0].data.cheer.id}`);
      await assert.rejects(call('family_unrelated','sendFamilyCheer',input),reason('UNRELATED_HOUSEHOLD'));
      await assert.rejects(call('elder_demo','sendFamilyCheer',input),reason('ROLE_NOT_ALLOWED'));
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      await assert.rejects(call('family_demo','sendFamilyCheer',input),reason('CONSENT_REQUIRED'));
      await assert.rejects(progress('family_demo','elder','elder_demo'),reason('CONSENT_REQUIRED'));
      await assert.rejects(read('family_demo',`cheers/${results[0].data.cheer.id}`),{code:'permission-denied'});
    });
    await t.test('phone help has helper impact but no outing/cheer; final notifications follow both confirmations',async()=>{
      for(const action of ['accept','start','finish','confirm'])await call('helper_demo','transitionRequest',cmd({requestId:'request_demo_ready',action}));
      assert.equal((await progress('helper_demo','helper','helper_demo')).counts.helpingSessions,0);assert.equal((await db.collection('notifications').get()).size,0);
      const done=(await call('elder_demo','transitionRequest',cmd({requestId:'request_demo_ready',action:'confirm'}))).data.request;
      assert.equal((await progress('elder_demo','elder','elder_demo')).counts.outings,0);
      assert.equal((await progress('helper_demo','helper','helper_demo')).counts.helpingSessions,1);
      await assert.rejects(call('family_demo','sendFamilyCheer',cmd({participationId:done.participationIds.elder})),reason('VERIFIED_OUTING_REQUIRED'));
      await assert.rejects(progress('family_demo','helper','helper_demo'),reason('PROGRESS_ACCESS_DENIED'));
      const notices=(await db.collection('notifications').get()).docs;assert.equal(notices.length,3);
      for(const n of notices){assert.equal(n.data().messageParams.state,'completed');assert.equal(JSON.stringify(n.data()).includes('amountCoins'),false);}
      await call('elder_demo','transitionRequest',cmd({requestId:'request_demo_ready',action:'confirm'}));assert.equal((await db.collection('notifications').get()).size,3);
    });
    await t.test('walks count once; ambiguous tasks remain pending; weekend/seeded aggregates are labelled and bounded',async()=>{
      const saturday=Date.parse(`${malaysiaDate(Timestamp.now())}T00:00:00+08:00`)-((new Date(Date.now()+8*3600000).getUTCDay()+1)%7)*86400000;
      await db.doc('requests/request_demo_ready').update({taskType:'walk_with_me',startsAt:Timestamp.fromMillis(saturday)});
      await complete();
      assert.equal((await progress('elder_demo','elder','elder_demo')).counts.outings,1);
      const household=await progress('helper_demo','household','household_helper',{periodType:'month'});
      assert.equal(household.counts.weekendGiveBack,2);assert.equal(household.includesSeededHistory,true);
      await assert.rejects(progress('family_demo','household','household_helper'),reason('UNRELATED_HOUSEHOLD'));
      const source=await stored('requests/request_demo_ready');
      await db.doc('requests/stage6_pending_task').set({...source,taskType:'sit_with_me',state:'assigned',elderConfirmation:null,helperConfirmation:null,completionEventId:null,completedAt:null});
      await complete('stage6_pending_task');
      const elder=await progress('elder_demo','elder','elder_demo');assert.equal(elder.counts.outings,1);assert.equal(elder.pendingOutingClassifications,1);assert.equal(elder.targets.outings,2);
      const coordinator=await progress('coordinator_demo','township',townshipId,{periodType:'month'});assert.equal(coordinator.counts.outings,3);assert.equal(coordinator.includesSeededHistory,true);
      await assert.rejects(progress('family_demo','township',townshipId),reason('SUMMARY_SUPPRESSED'));
    });
    await t.test('availability is a sanitized synthetic projection; private input and all direct mutations are denied',async()=>{
      const result=(await call('elder_demo','getAvailabilitySummary',{contractVersion:1})).data.availabilitySummary;
      assert.equal(result.isDemo,true);assert.equal(result.cells[0].helperCount,6);assert.deepEqual([result.cells[1].helperCount,result.cells[1].requestCount,result.cells[1].suppressed],[null,null,true]);
      assert.equal(JSON.stringify(result).includes('synthetic_retiree'),false);assert.equal(JSON.stringify(result).includes('helperIds'),false);
      assert.deepEqual((await read('elder_demo',`availabilitySummaries/${townshipId}`)).data().cells,result.cells);
      for(const uid of ['elder_demo','family_demo','helper_demo','coordinator_demo']){
        for(const path of [`availabilityDemoInputs/${townshipId}`,`progressTargets/${townshipId}`,'voiceLimits/elder_demo','demoProgressHistory/household_household_helper'])await assert.rejects(read(uid,path),{code:'permission-denied'});
        for(const path of ['reports/injected','notifications/injected','cheers/injected','helperBlocks/injected',`availabilitySummaries/${townshipId}`])await assert.rejects(setDoc(doc(clients.get(uid).fs,path),{injected:true}),{code:'permission-denied'});
      }
      const summary=(await call('coordinator_demo','getCoordinatorSummary',{contractVersion:1})).data.summary;
      assert.equal(summary.requests.assigned,1);assert.equal(summary.reports.new,0);assert.equal(summary.placeWarnings.active,1);
    });
    await t.test('voice provider receives no identity, creates no booking, rechecks consent after inference and applies an atomic per-user limit',async()=>{
      const fixed=ts('2026-10-22T00:00:00Z');await resetDemo(admin);await seedDemo(admin,fixed.toDate());let calls=0;
      const provider=async(context)=>{calls++;assert.equal(JSON.stringify(context).includes('elder_demo'),false);return {transcript:'Garden walk tomorrow',draft:{activityId:'activity_garden',taskType:'walk_with_me'}};};
      const voice=createVoiceService(db,provider,()=>fixed),input={contractVersion:1,elderId:'elder_demo',locale:'en',input:{type:'text',text:'Garden walk tomorrow'}};
      for(const uid of ['helper_demo','coordinator_demo','elder_solo','family_unrelated'])await assert.rejects(voice.parseVoiceBooking(uid,input));assert.equal(calls,0);
      await assert.rejects(voice.parseVoiceBooking('family_demo',input),reason('ROLE_NOT_ALLOWED'));
      const results=await Promise.allSettled(Array.from({length:6},()=>voice.parseVoiceBooking('elder_demo',input)));
      assert.equal(results.filter((r)=>r.status==='fulfilled').length,5);assert.equal(results.filter((r)=>r.status==='rejected'&&reason('VOICE_RATE_LIMIT')(r.reason)).length,1);
      const rate=await stored('voiceLimits/elder_demo');assert.deepEqual(Object.keys(rate).sort(),['count','minute','updatedAt']);
      assert.equal((await db.collection('requests').get()).size,1);assert.equal((await db.collection('participations').get()).size,0);assert.equal((await stored('wallets/elder_demo')).balance,0);
    });
    await t.test('voice transport errors and malformed output cannot persist transcript/audio or create domain effects',async()=>{
      const input={contractVersion:1,elderId:'elder_demo',locale:'bm',input:{type:'audio',mimeType:'audio/webm',base64:'YWJj'}};
      const voice=createVoiceService(db,async(context)=>{assert.equal(context.input.type,'audio');return {transcript:'secret words',draft:{elderId:'spoof'}};});
      await assert.rejects(voice.parseVoiceBooking('elder_demo',input),reason('VOICE_INVALID_RESPONSE'));
      assert.equal(JSON.stringify(await stored('voiceLimits/elder_demo')).includes('secret'),false);
      assert.equal((await db.collection('requests').get()).size,1);
    });
    await t.test('reset removes Stage 6 records/receipts only for known actors and preserves unrelated actors',async()=>{
      const report=(await call('elder_demo','submitReport',cmd({kind:'place_problem',placeId:'place_hall',text:'Review access.'}))).data.report;
      await call('elder_demo','blockHelper',cmd({elderId:'elder_demo',helperId:'helper_demo',reason:'Pause pairing.'}));
      await call('coordinator_demo','processDemoDueItems',cmd());
      const external=db.doc('reports/stage6_external_report');await external.set({createdBy:'stage6_external',townshipId,kind:'place_problem',text:'Other actor'});
      try{
        await resetDemo(admin);assert.equal(await stored(`reports/${report.id}`),undefined);assert.ok(await stored(external.path));
        assert.equal((await db.collection('helperBlocks').where('elderId','==','elder_demo').get()).size,0);
        assert.equal((await db.collection('notifications').where('recipientUid','==','coordinator_demo').get()).size,0);
        assert.equal((await db.collection('commandReceipts').where('functionName','==','submitReport').get()).size,0);
      }finally{await external.delete();}
    });
    await t.test('teammate fixtures match exact service response envelopes',async()=>{
      const fixtures=JSON.parse(await readFile(new URL('../docs/fixtures/stage6_coordination.json',import.meta.url),'utf8'));
      const now=ts(fixtures.serverTime);await resetDemo(admin);await seedDemo(admin,now.toDate());
      const services={...createOperationsService(db,()=>now),...createCheckInService(db,()=>now),...createNotificationService(db,()=>now),...createSummaryService(db,()=>now),...createAttendanceService(db,()=>now),
        ...createVoiceService(db,async()=>fixtures.voiceProviderFixture,()=>now)};
      for(const step of fixtures.steps)assert.deepEqual(await services[step.functionName](step.callerUid,step.input),step.output,step.functionName);
    });
  }finally{
    for(const {app,fs}of clients.values()){await terminate(fs);await deleteApp(app);}
    await resetDemo(admin);await seedDemo(admin);await db.terminate();await deleteAdminApp(admin.app);
  }
});
