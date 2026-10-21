import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {getFirestore,connectFirestoreEmulator,doc,getDocFromServer,getDocsFromServer,collection,query,where,orderBy,onSnapshot,terminate} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp as deleteAdminApp} from 'firebase-admin/app';
import {demoClients,seedDemo,resetDemo} from '../scripts/demo.mjs';
import {demoAccounts,demoPassword,townshipId} from '../scripts/fixtures.mjs';
import {projectId,region} from '../scripts/local.mjs';

const require = createRequire(import.meta.url);
const {createSessionService,reservationId,helperBlockId} = require('../functions/lib/sessions.js');
const {activityLockId,attendanceId,completionId,participationId} = require('../functions/lib/completions.js');
const {wireRecord} = require('../functions/lib/scheduling.js');
const command = (fields={}) => ({contractVersion:1,idempotencyKey:crypto.randomUUID(),...fields});
const reason = (expected) => (error) => error.details?.reason === expected;
const allDay = Array.from({length:7},(_,i)=>({weekday:i+1,startMinute:0,endMinute:1440}));

test('Stage 3 companion backend: authenticated APIs, races, rules and canonical completion', {timeout:300000}, async (t) => {
  const admin = await demoClients(), {db} = admin, clients = new Map();
  try {
    await resetDemo(admin);
    await seedDemo(admin);
    for (const account of demoAccounts) {
      const app = initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:demo'},crypto.randomUUID());
      const auth = getAuth(app); connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const firestore = getFirestore(app); connectFirestoreEmulator(firestore,'127.0.0.1',8080);
      const functions = getFunctions(app,region); connectFunctionsEmulator(functions,'127.0.0.1',5001);
      await signInWithEmailAndPassword(auth,account.email,demoPassword);
      clients.set(account.uid,{app,firestore,functions});
    }
    const call = async (uid,name,input) => (await httpsCallable(clients.get(uid).functions,name)(input)).data;
    const read = (uid,path) => getDocFromServer(doc(clients.get(uid).firestore,path));
    const stored = async (path) => (await db.doc(path).get()).data();
    const activity = async () => stored('activities/activity_garden');
    const booking = async (extra={}) => {
      const a = await activity();
      return command({elderId:'elder_demo',activityId:null,placeId:'place_garden',startsAt:a.startsAt.toDate().toISOString(),
        endsAt:a.endsAt.toDate().toISOString(),taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'female',...extra});
    };
    const create = async (extra={}) => (await call('elder_demo','createRequest',await booking(extra))).data.request;
    const assign = (id,extra={}) => call('coordinator_demo','assignRequest',command({requestId:id,pairingId:'pairing_demo',...extra}));
    const act = (uid,id,action) => call(uid,'transitionRequest',command({requestId:id,action}));
    const slots = async () => (await db.collection('helperReservations').get()).docs.flatMap((s)=>s.data().slots);
    t.beforeEach(async () => { await resetDemo(admin); await seedDemo(admin); });

    await t.test('all new callable endpoints require authentication and reject role or server-field spoofing', async () => {
      const app = initializeApp({projectId,apiKey:'local-demo-key'},crypto.randomUUID());
      try {
        const f = getFunctions(app,region); connectFunctionsEmulator(f,'127.0.0.1',5001);
        for (const [name,input] of [
          ['createRequest',await booking()],['assignRequest',command({requestId:'request_demo_ready',pairingId:'pairing_demo'})],
          ['setHelperAvailability',command({available:true,slots:allDay})],['transitionRequest',command({requestId:'request_demo_ready',action:'accept'})],
        ]) await assert.rejects(httpsCallable(f,name)(input),reason('AUTH_REQUIRED'));
      } finally { await deleteApp(app); }
      for (const uid of ['helper_demo','coordinator_demo']) await assert.rejects(call(uid,'createRequest',await booking()),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('elder_demo','setHelperAvailability',command({available:true,slots:allDay})),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('family_demo','assignRequest',command({requestId:'request_demo_ready',pairingId:'pairing_demo'})),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(call('helper_demo','setHelperAvailability',command({available:true,slots:allDay,tier:'T3'})),reason('UNKNOWN_FIELD'));
      await assert.rejects(call('elder_demo','createRequest',{...await booking(),completedAt:new Date().toISOString()}),reason('UNKNOWN_FIELD'));
      await db.doc('users/coordinator_demo').update({townshipId:'other'});
      await assert.rejects(assign('request_demo_ready'),reason('TOWNSHIP_NOT_ALLOWED'));
    });

    await t.test('availability returns data.helperProfile, preserves approval and accepted commitments, and retries safely', async () => {
      const before = await stored('helperProfiles/helper_demo');
      const input = command({available:false,slots:[{weekday:2,startMinute:600,endMinute:700},{weekday:1,startMinute:480,endMinute:600}]});
      const result = await call('helper_demo','setHelperAvailability',input);
      assert.deepEqual(result,{contractVersion:1,data:{helperProfile:wireRecord('helper_demo',await stored('helperProfiles/helper_demo'))}});
      for (const field of ['tier','approved','allowedTasks','languages','gender','createdAt']) assert.deepEqual(result.data.helperProfile[field],wireRecord('helper_demo',before)[field]);
      assert.equal(result.data.helperProfile.availabilitySlots[0].weekday,1);
      assert.equal((await stored('requests/request_demo_ready')).state,'assigned');
      assert.deepEqual(await call('helper_demo','setHelperAvailability',input),result);
      await assert.rejects(call('helper_demo','setHelperAvailability',{...input,available:true}),reason('IDEMPOTENCY_KEY_REUSED'));
      await assert.rejects(call('helper_demo','setHelperAvailability',command({available:true,slots:[{weekday:1,startMinute:0,endMinute:90},{weekday:1,startMinute:60,endMinute:120}]})),reason('INVALID_AVAILABILITY'));
    });

    await t.test('family booking consent is independent, current and rechecked on cached results and reads', async () => {
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      const input = await booking();
      const result = await call('family_demo','createRequest',input), id = result.data.request.id;
      assert.equal(result.data.request.createdBy,'family_demo');
      assert.equal(result.data.request.state,'requested');
      assert.deepEqual(await call('family_demo','createRequest',input),result);
      await read('family_demo',`requests/${id}`);
      await assert.rejects(call('family_unrelated','createRequest',await booking()),reason('UNRELATED_HOUSEHOLD'));
      await assert.rejects(call('elder_solo','createRequest',await booking()),reason('ROLE_NOT_ALLOWED'));
      const fs = clients.get('family_demo').firestore;
      let unsubscribe,listenerTimer;
      let initialReady;
      const initialSnapshot = new Promise((resolve) => { initialReady=resolve; });
      const revoked = new Promise((resolve,reject) => {
        listenerTimer = setTimeout(()=>reject(new Error('booking listener did not revoke')),15000);
        unsubscribe = onSnapshot(doc(fs,`requests/${id}`),initialReady,(error)=>{ clearTimeout(listenerTimer); resolve(error); });
      });
      try {
        await initialSnapshot;
        await call('elder_demo','saveElderSettings',command({familySharingEnabled:false,familyBookingEnabled:false,
          dueLocalTime:'09:00',graceMinutes:30,pauseToday:false}));
        // Use an independent server request: the SDK can reuse an already
        // synchronized listener target even for getDocFromServer().
        const token=await getAuth(clients.get('family_demo').app).currentUser.getIdToken();
        const freshRead=await fetch(`http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents/requests/${id}`,
          {headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(10000)});
        assert.equal(freshRead.status,403,await freshRead.text());
        await assert.rejects(call('family_demo','createRequest',input),reason('CONSENT_REQUIRED'));
        await assert.rejects(act('family_demo',id,'cancel'),reason('CONSENT_REQUIRED'));
        // A must tear down cached views on the household access flag. A request
        // listener is re-authorized when its next result would be delivered.
        await assign(id);
        assert.equal((await revoked).code,'permission-denied');
        await assert.rejects(read('family_demo',`requests/${id}`),{code:'permission-denied'});
        await read('elder_demo',`requests/${id}`);
      } finally { clearTimeout(listenerTimer); unsubscribe?.(); }
    });

    await t.test('request creation validates activities and prevents different-key/actor duplicate activity bookings', async () => {
      await assert.rejects(create({taskType:'phone_help'}),reason('INVALID_PLACE'));
      await assert.rejects(create({activityId:'activity_garden',endsAt:new Date((await activity()).endsAt.toMillis()+60000).toISOString()}),reason('ACTIVITY_SCHEDULE_MISMATCH'));
      const results = await Promise.allSettled([
        call('elder_demo','createRequest',await booking({activityId:'activity_garden'})),
        call('family_demo','createRequest',await booking({activityId:'activity_garden'})),
      ]);
      assert.equal(results.filter((r)=>r.status==='fulfilled').length,1);
      assert.equal(results.find((r)=>r.status==='rejected').reason.details.reason,'ACTIVITY_REQUEST_EXISTS');
      const id = results.find((r)=>r.status==='fulfilled').value.data.request.id;
      assert.equal((await stored(`activityElderLocks/${activityLockId('activity_garden','elder_demo')}`)).requestId,id);
      await act('elder_demo',id,'cancel');
      assert.equal(await stored(`activityElderLocks/${activityLockId('activity_garden','elder_demo')}`),undefined);
      assert.equal((await create({activityId:'activity_garden'})).state,'requested');
    });

    await t.test('assignment rechecks pairing, tier, task, preferences, availability, trial, cadence and blocks without partial reservations', async () => {
      const request = await create();
      const pairRef = db.doc('pairings/pairing_demo'), profileRef=db.doc('helperProfiles/helper_demo');
      const originalPair = await stored(pairRef.path), originalProfile=await stored(profileRef.path);
      const cases = [
        [pairRef,{active:false},'PAIRING_NOT_ELIGIBLE'],[pairRef,{elderAccepted:false},'PAIRING_NOT_ELIGIBLE'],
        [pairRef,{helperAccepted:false},'PAIRING_NOT_ELIGIBLE'],[pairRef,{allowedTasks:['phone_help']},'PAIRING_NOT_ELIGIBLE'],
        [pairRef,{trialEndsOn:'2000-01-01'},'PAIRING_NOT_ELIGIBLE'],[pairRef,{cadence:[]},'PAIRING_NOT_ELIGIBLE'],
        [pairRef,{trialStartsOn:null},'PAIRING_NOT_ELIGIBLE'],
        [profileRef,{approved:false},'PAIRING_NOT_ELIGIBLE'],[profileRef,{tier:'T1'},'PAIRING_NOT_ELIGIBLE'],
        [profileRef,{allowedTasks:['phone_help']},'PAIRING_NOT_ELIGIBLE'],[profileRef,{languages:['bm']},'PAIRING_NOT_ELIGIBLE'],
        [profileRef,{gender:'male'},'PAIRING_NOT_ELIGIBLE'],[profileRef,{available:false},'HELPER_UNAVAILABLE'],
        [profileRef,{availabilitySlots:[]},'HELPER_UNAVAILABLE'],
      ];
      for (const [ref,patch,error] of cases) {
        await ref.update(patch);
        await assert.rejects(assign(request.id),reason(error));
        assert.equal((await stored(`requests/${request.id}`)).state,'requested');
        assert.equal((await slots()).filter((s)=>s.requestId===request.id).length,0);
        await pairRef.set(originalPair); await profileRef.set(originalProfile);
      }
      const blockRef=db.doc(`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`);
      try { await blockRef.set({elderId:'elder_demo',helperId:'helper_demo',townshipId}); await assert.rejects(assign(request.id),reason('HELPER_BLOCKED')); }
      finally { await blockRef.delete(); }
      const input=command({requestId:request.id,pairingId:'pairing_demo'});
      const results=await Promise.all([call('coordinator_demo','assignRequest',input),call('coordinator_demo','assignRequest',input)]);
      assert.deepEqual(results[0],results[1]);
      assert.equal((await slots()).filter((s)=>s.requestId===request.id).length,1);
      assert.equal(results[0].data.request.state,'assigned');
    });

    await t.test('racing overlapping assignments reserve once; adjacent bookings work and cancellation releases capacity', async () => {
      const a=await create(), b=await create();
      const results=await Promise.allSettled([assign(a.id),assign(b.id)]);
      assert.equal(results.filter((r)=>r.status==='fulfilled').length,1);
      assert.equal(results.find((r)=>r.status==='rejected').reason.details.reason,'HELPER_UNAVAILABLE');
      const winner=results[0].status==='fulfilled'?a:b, loser=winner===a?b:a;
      const adjacent=await create({startsAt:a.endsAt,endsAt:new Date(Date.parse(a.endsAt)+3600000).toISOString()});
      await assign(adjacent.id);
      await assert.rejects(act('helper_demo',winner.id,'cancel'),reason('ROLE_NOT_ALLOWED'));
      await act('family_demo',winner.id,'cancel');
      assert.equal((await assign(loser.id)).data.request.state,'assigned');
      assert.equal((await slots()).some((s)=>s.requestId===winner.id),false);
      assert.equal((await act('coordinator_demo',winner.id,'cancel')).data.request.state,'cancelled');
    });

    await t.test('ready demo completes through real callables only after two distinct confirmations, without coins or outing credit', async () => {
      const id='request_demo_ready';
      for (const action of ['start','finish']) await assert.rejects(act('elder_demo',id,action),reason('NOT_ASSIGNED_HELPER'));
      await assert.rejects(act('helper_demo',id,'finish'),reason('INVALID_TRANSITION'));
      assert.equal((await act('helper_demo',id,'accept')).data.request.state,'accepted');
      assert.equal((await act('helper_demo',id,'start')).data.request.state,'in_progress');
      await assert.rejects(act('elder_demo',id,'cancel'),reason('INVALID_TRANSITION'));
      await act('helper_demo',id,'finish');
      for (const uid of ['family_demo','coordinator_demo']) await assert.rejects(act(uid,id,'confirm'),reason('ROLE_NOT_ALLOWED'));
      const first=await act('helper_demo',id,'confirm');
      assert.equal(first.data.request.state,'awaiting_confirmation');
      assert.equal(first.data.request.elderConfirmation,null);
      assert.equal((await db.collection('participations').get()).size,0);
      assert.deepEqual(await act('helper_demo',id,'confirm'),first);
      const input=command({requestId:id,action:'confirm'});
      const results=await Promise.all([call('elder_demo','transitionRequest',input),call('elder_demo','transitionRequest',input)]);
      assert.deepEqual(results[0],results[1]);
      const done=results[0].data.request;
      assert.equal(done.state,'completed'); assert.equal(done.completedAt,done.elderConfirmation.at);
      assert.deepEqual(await act('elder_demo',id,'confirm'),results[0]);
      assert.equal((await db.collection('completionEvents').get()).size,1);
      for (const role of ['elder','helper']) {
        const pid=done.participationIds[role];
        assert.equal(pid,participationId(completionId(null,id),`${role}_demo`));
        const claim=await stored(`rewardClaims/${pid}`);
        assert.equal(claim.status,'pending_policy'); assert.equal(claim.amountCoins,null); assert.equal(claim.eligible,null);
        assert.equal((await stored(`completionMarkers/${pid}`)).outingClassification,'does_not_count');
        assert.equal((await stored(`wallets/${role}_demo`)).balance,0);
        assert.equal((await db.collection(`wallets/${role}_demo/entries`).get()).size,0);
      }
      assert.equal((await slots()).some((s)=>s.requestId===id),false);
      assert.equal((await stored('helperSessions/helper_demo')).requestId,null);
    });

    await t.test('server clocks enforce activity attendance; concurrent elder/helper confirmation uses one canonical event and participation', async () => {
      let now=Timestamp.now(); const service=createSessionService(db,()=>now);
      const r=await create({activityId:'activity_garden'}); await assign(r.id);
      const transition=(uid,action)=>service.transitionRequest(uid,command({requestId:r.id,action}));
      await transition('helper_demo','accept');
      await assert.rejects(transition('helper_demo','start'),reason('SESSION_NOT_STARTED'));
      now=Timestamp.fromMillis(Date.parse(r.startsAt)); await transition('helper_demo','start');
      await assert.rejects(transition('helper_demo','finish'),reason('ACTIVITY_NOT_FINISHED'));
      now=Timestamp.fromMillis(Date.parse(r.endsAt)); await transition('helper_demo','finish');
      const results=await Promise.all([transition('elder_demo','confirm'),transition('helper_demo','confirm')]);
      assert.equal(results.filter((v)=>v.data.request.state==='completed').length,1);
      const completed=(await stored(`requests/${r.id}`));
      const eventId=completionId('activity_garden',r.id), pid=participationId(eventId,'elder_demo');
      assert.equal(completed.completionEventId,eventId);
      const attendance=await stored(`activityAttendances/${attendanceId('activity_garden','elder_demo')}`);
      assert.equal(attendance.verificationMethod,'mutual_session_confirmation'); assert.equal(attendance.participationId,pid);
      assert.equal((await stored(`activityElderLocks/${activityLockId('activity_garden','elder_demo')}`)).state,'completed');
      assert.equal((await stored(`completionMarkers/${pid}`)).outingClassification,'counts');
      await read('family_demo',`activityAttendances/${attendanceId('activity_garden','elder_demo')}`);
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      await assert.rejects(read('family_demo',`activityAttendances/${attendanceId('activity_garden','elder_demo')}`),{code:'permission-denied'});
      await read('family_demo',`requests/${r.id}`);
      assert.equal((await db.collection('participations').get()).size,2);
      assert.equal((await db.collection('rewardClaims').get()).size,2);
      await assert.rejects(create({activityId:'activity_garden'}),reason('ACTIVITY_ALREADY_COMPLETED'));
    });

    await t.test('existing canonical attendance, claims and first verification survive companion representation and retries', async () => {
      let now=Timestamp.now(); const service=createSessionService(db,()=>now);
      const r=await create({activityId:'activity_garden'}); await assign(r.id);
      const transition=(uid,action)=>service.transitionRequest(uid,command({requestId:r.id,action}));
      await transition('helper_demo','accept'); now=Timestamp.fromMillis(Date.parse(r.startsAt)); await transition('helper_demo','start');
      now=Timestamp.fromMillis(Date.parse(r.endsAt)); await transition('helper_demo','finish');
      // Defensive convergence against an already verified standalone representation.
      const eid=completionId('activity_garden',r.id), pid=participationId(eid,'elder_demo'), first=Timestamp.fromMillis(now.toMillis()-1);
      const participant={completionEventId:eid,townshipId,beneficiaryUid:'elder_demo',beneficiaryRole:'elder',sourceRequestIds:[],verifiedAt:first,createdAt:first};
      await db.doc(`completionEvents/${eid}`).set({townshipId,firstVerifiedAt:first});
      await db.doc(`participations/${pid}`).set(participant);
      const claim={...participant,participationId:pid,status:'pending_policy',amountCoins:null};
      await db.doc(`rewardClaims/${pid}`).set(claim);
      const attendance={elderId:'elder_demo',householdId:'household_demo',townshipId,status:'verified',mode:'standalone',verificationMethod:'coordinator_review',verifiedAt:first};
      await db.doc(`activityAttendances/${attendanceId('activity_garden','elder_demo')}`).set(attendance);
      await transition('elder_demo','confirm'); await transition('helper_demo','confirm');
      assert.deepEqual(await stored(`rewardClaims/${pid}`),claim);
      assert.deepEqual(await stored(`activityAttendances/${attendanceId('activity_garden','elder_demo')}`),attendance);
      assert.equal((await stored(`participations/${pid}`)).verifiedAt.toMillis(),first.toMillis());
      assert.deepEqual((await stored(`participations/${pid}`)).sourceRequestIds,[r.id]);
      assert.equal((await db.collection('participations').get()).size,2);
      assert.equal((await db.collection('rewardClaims').get()).size,2);
    });

    await t.test('in-progress helper lock prevents overruns from starting another session; finish releases it', async () => {
      let now=Timestamp.now(); const service=createSessionService(db,()=>now);
      const a=await create({taskType:'phone_help',placeId:null});
      const b=await create({taskType:'phone_help',placeId:null,startsAt:a.endsAt,endsAt:new Date(Date.parse(a.endsAt)+3600000).toISOString()});
      await assign(a.id); await assign(b.id);
      const transition=(id,action)=>service.transitionRequest('helper_demo',command({requestId:id,action}));
      await transition(a.id,'accept'); await transition(b.id,'accept');
      now=Timestamp.fromMillis(Date.parse(a.startsAt)); await transition(a.id,'start');
      now=Timestamp.fromMillis(Date.parse(b.startsAt));
      await assert.rejects(transition(b.id,'start'),reason('HELPER_BUSY'));
      await transition(a.id,'finish');
      assert.equal((await transition(b.id,'start')).data.request.state,'in_progress');
      const block=db.doc(`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`);
      try { await block.set({elderId:'elder_demo',helperId:'helper_demo'});
        // Safety restrictions do not strand an already started session.
        assert.equal((await transition(b.id,'finish')).data.request.state,'awaiting_confirmation');
      } finally { await block.delete(); }
    });

    await t.test('approval and blocks are rechecked on acceptance/start; expired activities cannot be started', async () => {
      let now=Timestamp.now(); const service=createSessionService(db,()=>now);
      const r=await create({activityId:'activity_garden'}); await assign(r.id);
      const transition=(action)=>service.transitionRequest('helper_demo',command({requestId:r.id,action}));
      await db.doc('helperProfiles/helper_demo').update({approved:false});
      await assert.rejects(transition('accept'),reason('PAIRING_NOT_ELIGIBLE'));
      await db.doc('helperProfiles/helper_demo').update({approved:true}); await transition('accept');
      now=Timestamp.fromMillis(Date.parse(r.startsAt));
      const block=db.doc(`helperBlocks/${helperBlockId('elder_demo','helper_demo')}`);
      try { await block.set({elderId:'elder_demo',helperId:'helper_demo'}); await assert.rejects(transition('start'),reason('HELPER_BLOCKED')); }
      finally { await block.delete(); }
      now=Timestamp.fromMillis(Date.parse(r.endsAt)); await assert.rejects(transition('start'),reason('ACTIVITY_ALREADY_FINISHED'));
    });

    await t.test('scoped client queries, separate booking/sharing reads and private completion/finance boundaries hold', async () => {
      const r=await create(); await assign(r.id);
      for (const uid of ['elder_demo','family_demo','helper_demo','coordinator_demo']) await read(uid,`requests/${r.id}`);
      for (const uid of ['elder_solo','family_unrelated']) await assert.rejects(read(uid,`requests/${r.id}`),{code:'permission-denied'});
      for (const [uid,filters] of [
        ['elder_demo',[where('elderId','==','elder_demo'),orderBy('startsAt','desc')]],
        ['family_demo',[where('elderId','==','elder_demo'),where('householdId','==','household_demo'),orderBy('startsAt','desc')]],
        ['helper_demo',[where('helperId','==','helper_demo'),where('townshipId','==',townshipId),orderBy('startsAt')]],
        ['coordinator_demo',[where('townshipId','==',townshipId),where('state','==','assigned'),orderBy('startsAt')]],
      ]) {
        const fs=clients.get(uid).firestore;
        await assert.doesNotReject(async()=>assert.ok((await getDocsFromServer(query(collection(fs,'requests'),...filters))).size>=1),`${uid} scoped request query`);
        await assert.rejects(getDocsFromServer(collection(fs,'requests')),{code:'permission-denied'});
      }
      for (const action of ['accept','start','finish']) await act('helper_demo','request_demo_ready',action);
      await act('elder_demo','request_demo_ready','confirm'); const done=(await act('helper_demo','request_demo_ready','confirm')).data.request;
      const pid=done.participationIds.elder;
      for (const collection of ['participations','rewardClaims']) {
        for (const uid of ['elder_demo','coordinator_demo']) await read(uid,`${collection}/${pid}`);
        for (const uid of ['family_demo','helper_demo']) await assert.rejects(read(uid,`${collection}/${pid}`),{code:'permission-denied'});
      }
      for (const path of [`completionEvents/${done.completionEventId}`,`completionMarkers/${pid}`,'helperSessions/helper_demo',
        `helperReservations/${reservationId('helper_demo',new Date(Date.parse(r.startsAt)+8*3600000).toISOString().slice(0,10))}`]) {
        await assert.rejects(read('coordinator_demo',path),{code:'permission-denied'});
      }
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false}); await read('family_demo',`requests/${r.id}`);
      await db.doc('elderSettings/elder_demo').update({familyBookingEnabled:false,familySharingEnabled:true});
      await assert.rejects(read('family_demo',`requests/${r.id}`),{code:'permission-denied'});
    });

    await t.test('published JSON examples match clock-injected real service response envelopes', async () => {
      const fixtures=JSON.parse(await readFile(new URL('../docs/fixtures/stage3_sessions.json',import.meta.url),'utf8'));
      let now=Timestamp.fromDate(new Date(fixtures.serverTime));
      await resetDemo(admin); await seedDemo(admin,now.toDate());
      const service=createSessionService(db,()=>now);
      assert.deepEqual(await service.setHelperAvailability('helper_demo',fixtures.availability.input),fixtures.availability.output);
      const created=await service.createRequest('elder_demo',fixtures.create.input);
      assert.deepEqual(created,fixtures.create.output);
      assert.deepEqual(await service.assignRequest('coordinator_demo',fixtures.assign.input),fixtures.assign.output);
      assert.deepEqual(await service.transitionRequest('helper_demo',fixtures.accept.input),fixtures.accept.output);
      for (const name of ['start','finish','helperConfirm','elderConfirm']) {
        const scenario=fixtures[name]; now=Timestamp.fromDate(new Date(scenario.at));
        assert.deepEqual(await service.transitionRequest(scenario.callerUid,scenario.input),scenario.output);
      }
      for (const claim of fixtures.claimExamples) assert.deepEqual(wireRecord(claim.id,await stored(`rewardClaims/${claim.id}`)),claim);
    });

    await t.test('reset removes owned sessions, reservations and completions while preserving shared events and unrelated data', async () => {
      const id='request_demo_ready';
      for (const action of ['accept','start','finish']) await act('helper_demo',id,action);
      await act('elder_demo',id,'confirm'); const done=(await act('helper_demo',id,'confirm')).data.request;
      const externalId='stage3_external_participant', externalReservation='stage3_external_request';
      const ready=await stored(`requests/${id}`), date=new Date(ready.startsAt.toMillis()+8*3600000).toISOString().slice(0,10);
      const reservationRef=db.doc(`helperReservations/${reservationId('helper_demo',date)}`);
      await reservationRef.set({helperId:'helper_demo',townshipId,localDate:date,slots:[{requestId:externalReservation,startsAt:ready.startsAt,endsAt:ready.endsAt}]});
      await db.doc(`participations/${externalId}`).set({beneficiaryUid:'external',completionEventId:done.completionEventId,sourceRequestIds:[externalReservation]});
      await db.doc(`requests/${externalReservation}`).set({elderId:'external',townshipId,helperId:'helper_demo'});
      await db.doc('helperSessions/helper_demo').set({helperId:'helper_demo',requestId:externalReservation});
      try {
        await resetDemo(admin);
        assert.equal(await stored(`requests/${id}`),undefined);
        assert.equal(await stored(`participations/${done.participationIds.elder}`),undefined);
        assert.equal(await stored(`rewardClaims/${done.participationIds.helper}`),undefined);
        assert.equal(await stored(`completionMarkers/${done.participationIds.elder}`),undefined);
        assert.ok(await stored(`completionEvents/${done.completionEventId}`));
        assert.ok(await stored(`participations/${externalId}`));
        assert.equal((await stored('helperSessions/helper_demo')).requestId,externalReservation);
        await seedDemo(admin);
        assert.ok((await stored(reservationRef.path)).slots.some((s)=>s.requestId===externalReservation));
        assert.ok(await stored(`requests/${externalReservation}`));
        assert.equal((await db.collection('commandReceipts').where('functionName','==','transitionRequest').get()).size,0);
      } finally {
        await db.doc(`participations/${externalId}`).delete(); await db.doc(`requests/${externalReservation}`).delete();
        await db.doc(`completionEvents/${done.completionEventId}`).delete(); await db.doc('helperSessions/helper_demo').delete();
        await reservationRef.delete();
      }
    });
  } finally {
    for (const {app,firestore} of clients.values()) { await terminate(firestore); await deleteApp(app); }
    await resetDemo(admin); await seedDemo(admin);
    await db.terminate(); await deleteAdminApp(admin.app);
  }
});
