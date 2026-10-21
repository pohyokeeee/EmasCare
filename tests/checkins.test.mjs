import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {initializeApp, deleteApp} from 'firebase/app';
import {connectAuthEmulator, getAuth, signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore, connectFirestoreEmulator, doc, getDocFromServer, getDocsFromServer,
  collection, query, where, orderBy, onSnapshot, terminate} from 'firebase/firestore';
import {getFunctions, connectFunctionsEmulator, httpsCallable} from 'firebase/functions';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp as deleteAdminApp} from 'firebase-admin/app';
import {demoClients, seedDemo, resetDemo} from '../scripts/demo.mjs';
import {demoAccounts, demoPassword, townshipId} from '../scripts/fixtures.mjs';
import {projectId, region} from '../scripts/local.mjs';

const require = createRequire(import.meta.url);
const {createCheckInService, malaysiaDate} = require('../functions/lib/checkins.js');
const {tupleId} = require('../functions/lib/commands.js');
const version = {contractVersion:1};
const key = (prefix) => `${prefix}-${crypto.randomUUID()}`;
const settingsInput = (extra = {}) => ({...version,idempotencyKey:key('settings'),familySharingEnabled:true,
  familyBookingEnabled:true,dueLocalTime:'09:00',graceMinutes:30,pauseToday:false,...extra});
const command = (extra = {}) => ({...version,idempotencyKey:key('checkin'),...extra});
const reason = (expected) => (error) => error.details?.reason === expected;
const wire = (data) => Object.fromEntries(Object.entries(data).map(([name,value]) =>
  [name, typeof value?.toDate === 'function' ? value.toDate().toISOString() : value]));

test('Stage 2 real Auth/callable/client-read journey', {timeout:240000}, async (t) => {
  const admin = await demoClients();
  const {db} = admin;
  const clients = new Map();
  try {
    await resetDemo(admin);
    await seedDemo(admin);
    for (const account of demoAccounts) {
      const app = initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:emascare-demo'},key(account.uid));
      const auth = getAuth(app);
      connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const firestore = getFirestore(app);
      connectFirestoreEmulator(firestore,'127.0.0.1',8080);
      const functions = getFunctions(app,region);
      connectFunctionsEmulator(functions,'127.0.0.1',5001);
      await signInWithEmailAndPassword(auth,account.email,demoPassword);
      clients.set(account.uid,{app,firestore,functions});
    }
    const client = (uid) => clients.get(uid);
    const call = async (uid,name,input) => (await httpsCallable(client(uid).functions,name)(input)).data;
    const read = (uid,path) => getDocFromServer(doc(client(uid).firestore,path));
    const localDate = malaysiaDate(Timestamp.now());
    const id = `elder_demo_${localDate}`;
    const freshPrimary = async () => {
      await db.doc(`checkins/${id}`).delete();
      await db.doc(`dailyStatuses/${id}`).delete();
      return call('elder_demo','saveElderSettings',settingsInput());
    };

    await t.test('settings return data.settings and update both consent projections atomically', async () => {
      const before = (await db.doc('elderSettings/elder_demo').get()).data();
      const input = settingsInput({familyBookingEnabled:false});
      const result = await call('elder_demo','saveElderSettings',input);
      assert.deepEqual(Object.keys(result).sort(),['contractVersion','data']);
      assert.deepEqual(Object.keys(result.data),['settings']);
      const stored = (await db.doc('elderSettings/elder_demo').get()).data();
      assert.deepEqual(result.data.settings,{id:'elder_demo',...wire(stored)});
      assert.equal(stored.createdAt.toMillis(),before.createdAt.toMillis());
      assert.equal(stored.familySharingEnabled,true);
      assert.equal(stored.familyBookingEnabled,false);
      assert.deepEqual((await db.doc('households/household_demo').get()).data().elderAccess.elder_demo,
        {displayName:'Demo Elder',familySharingEnabled:true,familyBookingEnabled:false});
      assert.deepEqual(await call('elder_demo','saveElderSettings',input),result);
      await assert.rejects(call('elder_demo','saveElderSettings',{...input,graceMinutes:45}),reason('IDEMPOTENCY_KEY_REUSED'));
    });

    await t.test('all three Stage 2 callables reject an unsigned client', async () => {
      const app = initializeApp({projectId,apiKey:'local-demo-key'},key('unsigned'));
      try {
        const functions = getFunctions(app,region);
        connectFunctionsEmulator(functions,'127.0.0.1',5001);
        for (const [name,input] of [['saveElderSettings',settingsInput()],['submitCheckIn',command()],
          ['recordPhoneResponse',command({elderId:'elder_demo'})]]) {
          await assert.rejects(httpsCallable(functions,name)(input),reason('AUTH_REQUIRED'));
        }
      } finally { await deleteApp(app); }
    });

    await t.test('only the actual elder can change settings or submit; only a coordinator can record a phone response', async () => {
      for (const uid of ['family_demo','family_unrelated','helper_demo','coordinator_demo']) {
        await assert.rejects(call(uid,'saveElderSettings',settingsInput()),reason('ROLE_NOT_ALLOWED'));
        await assert.rejects(call(uid,'submitCheckIn',command()),reason('ROLE_NOT_ALLOWED'));
      }
      for (const uid of ['elder_demo','family_demo','helper_demo']) {
        await assert.rejects(call(uid,'recordPhoneResponse',command({elderId:'elder_demo'})),reason('ROLE_NOT_ALLOWED'));
      }
      await assert.rejects(call('elder_demo','submitCheckIn',command({elderId:'elder_solo'})),reason('UNKNOWN_FIELD'));
      await assert.rejects(call('elder_demo','submitCheckIn',command({localDate:'2026-01-01'})),reason('UNKNOWN_FIELD'));
    });

    await t.test('Saya OK persists one original submission across concurrent retries and distinct keys', async () => {
      await freshPrimary();
      const input = command();
      const results = await Promise.all([input,input,command()].map((payload) => call('elder_demo','submitCheckIn',payload)));
      for (const result of results) assert.deepEqual(result,results[0]);
      const result = results[0];
      const stored = (await db.doc(`checkins/${id}`).get()).data();
      assert.equal(stored.state,'ok');
      assert.equal(stored.source,'app');
      assert.equal(stored.recordedBy,'elder_demo');
      assert.ok(stored.submittedAt instanceof Timestamp);
      assert.deepEqual(result.data.checkin,{id,...wire(stored)});
      assert.deepEqual(Object.keys(result.data.dailyStatus).sort(),['id','elderId','householdId','localDate','state','submittedAt','updatedAt'].sort());
      assert.deepEqual(result.data.dailyStatus,{id,...wire((await db.doc(`dailyStatuses/${id}`).get()).data())});
      assert.equal((await db.collection('checkins').where('elderId','==','elder_demo').where('localDate','==',localDate).get()).size,1);
      // Read via a newly established authenticated client request, not the callable result/cache.
      assert.equal((await read('family_demo',`dailyStatuses/${id}`)).data().state,'ok');
      await assert.rejects(read('family_demo',`checkins/${id}`));
      await assert.rejects(read('family_unrelated',`dailyStatuses/${id}`));
      await assert.rejects(read('helper_demo',`dailyStatuses/${id}`));
      assert.equal((await read('elder_demo',`checkins/${id}`)).data().source,'app');
    });

    await t.test('consent withdrawal closes the active family stream and old history; booking consent stays independent', async () => {
      const familyDb = client('family_demo').firestore;
      let unsubscribe;
      let initialResolve;
      const initial = new Promise((resolve) => { initialResolve = resolve; });
      let timer;
      const deniedStream = new Promise((resolve,reject) => {
        timer = setTimeout(() => reject(new Error('Family listener did not lose access after withdrawal')),15000);
        unsubscribe = onSnapshot(doc(familyDb,`dailyStatuses/${id}`),() => initialResolve(),(error) => {
          clearTimeout(timer);
          if (error.code !== 'permission-denied') reject(error); else resolve();
        });
      });
      try {
        await initial;
        await call('elder_demo','saveElderSettings',settingsInput({familySharingEnabled:false,familyBookingEnabled:true}));
        await deniedStream;
        await assert.rejects(read('family_demo',`dailyStatuses/${id}`));
        const history = query(collection(familyDb,'dailyStatuses'),where('elderId','==','elder_demo'),
          where('householdId','==','household_demo'),orderBy('localDate','desc'));
        await assert.rejects(getDocsFromServer(history));
        // A consent change never deletes the underlying response or grants access to finances.
        assert.equal((await read('elder_demo',`checkins/${id}`)).data().state,'ok');
        assert.equal((await db.doc('elderSettings/elder_demo').get()).data().familyBookingEnabled,true);
        await call('family_demo','foundationProbe',command({townshipId,note:'booking remains allowed',elderId:'elder_demo',consentScope:'family_booking'}));
        await assert.rejects(call('family_demo','foundationProbe',command({townshipId,note:'sharing revoked',elderId:'elder_demo',consentScope:'daily_sharing'})),reason('CONSENT_REQUIRED'));
        await call('elder_demo','saveElderSettings',settingsInput({familySharingEnabled:true,familyBookingEnabled:false}));
        assert.equal((await read('family_demo',`dailyStatuses/${id}`)).data().state,'ok');
        await assert.rejects(call('family_demo','foundationProbe',command({townshipId,note:'booking revoked',elderId:'elder_demo',consentScope:'family_booking'})),reason('CONSENT_REQUIRED'));
        await assert.rejects(read('family_demo','wallets/elder_demo'));
      } finally {
        clearTimeout(timer);
        unsubscribe?.();
        await call('elder_demo','saveElderSettings',settingsInput());
      }
    });

    await t.test('pause rejects app and phone submissions, unpause resumes, and pause preserves existing Saya OK', async () => {
      await freshPrimary();
      const paused = await call('elder_demo','saveElderSettings',settingsInput({pauseToday:true}));
      assert.equal(paused.data.settings.pausedOn,localDate);
      assert.equal((await read('family_demo',`dailyStatuses/${id}`)).data().state,'paused');
      await assert.rejects(call('elder_demo','submitCheckIn',command()),reason('CHECKIN_PAUSED'));
      await assert.rejects(call('coordinator_demo','recordPhoneResponse',command({elderId:'elder_demo'})),reason('CHECKIN_PAUSED'));
      await call('elder_demo','saveElderSettings',settingsInput());
      const checked = await call('elder_demo','submitCheckIn',command());
      await call('elder_demo','saveElderSettings',settingsInput({pauseToday:true}));
      assert.deepEqual((await call('elder_demo','submitCheckIn',command())).data,checked.data);
      assert.equal((await read('family_demo',`dailyStatuses/${id}`)).data().state,'ok');
    });

    await t.test('coordinator phone response is township scoped, server attributed and cannot replace an existing app response', async () => {
      const before = (await db.doc(`checkins/${id}`).get()).data();
      const repeat = await call('coordinator_demo','recordPhoneResponse',command({elderId:'elder_demo'}));
      assert.equal(repeat.data.checkin.source,'app');
      assert.equal(repeat.data.checkin.submittedAt,before.submittedAt.toDate().toISOString());
      const input = command({elderId:'elder_solo'});
      const phone = await call('coordinator_demo','recordPhoneResponse',input);
      assert.equal(phone.data.checkin.source,'coordinator_phone');
      assert.equal(phone.data.checkin.recordedBy,'coordinator_demo');
      assert.equal(phone.data.dailyStatus.state,'ok');
      assert.equal(Object.hasOwn(phone.data.dailyStatus,'recordedBy'),false);
      await db.doc('users/coordinator_demo').update({townshipId:'other_township'});
      try { await assert.rejects(call('coordinator_demo','recordPhoneResponse',input),reason('TOWNSHIP_NOT_ALLOWED')); }
      finally { await db.doc('users/coordinator_demo').update({townshipId}); }
    });

    await t.test('receipt replay rechecks current household membership and cannot rewrite newer consent', async () => {
      const input = settingsInput({familySharingEnabled:true});
      const original = await call('elder_demo','saveElderSettings',input);
      await call('elder_demo','saveElderSettings',settingsInput({familySharingEnabled:false}));
      assert.deepEqual(await call('elder_demo','saveElderSettings',input),original);
      assert.equal((await db.doc('elderSettings/elder_demo').get()).data().familySharingEnabled,false);
      await db.doc('households/household_demo').update({elderIds:[]});
      try { await assert.rejects(call('elder_demo','saveElderSettings',input),reason('UNRELATED_HOUSEHOLD')); }
      finally { await db.doc('households/household_demo').update({elderIds:['elder_demo']}); }
    });

    await t.test('concurrent pause and check-in leave a consistent state with no rewarded check-in', async () => {
      await freshPrimary();
      const results = await Promise.allSettled([
        call('elder_demo','saveElderSettings',settingsInput({pauseToday:true})),
        call('elder_demo','submitCheckIn',command()),
      ]);
      assert.equal(results[0].status,'fulfilled');
      if (results[1].status === 'rejected') assert.equal(results[1].reason.details.reason,'CHECKIN_PAUSED');
      const checkin = (await db.doc(`checkins/${id}`).get()).data();
      const status = (await db.doc(`dailyStatuses/${id}`).get()).data();
      assert.equal(status.state,checkin.state);
      assert.ok(['paused','ok'].includes(checkin.state));
      assert.equal(checkin.submittedAt !== null,checkin.state === 'ok');
      assert.equal((await db.doc('elderSettings/elder_demo').get()).data().pausedOn,localDate);
      for (const owner of ['elder_demo','helper_demo']) assert.equal((await db.doc(`wallets/${owner}`).get()).data().balance,0);
      assert.equal((await db.collection('rewardClaims').get()).size,0);
    });
  } finally {
    for (const client of clients.values()) { await terminate(client.firestore); await deleteApp(client.app); }
    await db.terminate();
    await deleteAdminApp(admin.app);
  }
});

test('Stage 2 internal service: midnight, late response, failure rollback and scoped reset', {timeout:120000}, async (t) => {
  const admin = await demoClients();
  const {db} = admin;
  const receiptIds = [];
  const dates = ['2026-12-31','2027-01-01','2027-01-02'];
  let now = Timestamp.fromDate(new Date('2026-12-31T15:59:59Z'));
  const service = createCheckInService(db,() => now);
  const internal = (name,input,uid = 'elder_demo') => {
    receiptIds.push(tupleId(uid,name,input.idempotencyKey));
    return service[name](uid,input);
  };
  try {
    await t.test('published Stage 2 JSON examples match actual service outputs', async () => {
      const examples = JSON.parse(await readFile(new URL('../docs/fixtures/stage2_checkins.json',import.meta.url),'utf8'));
      const seededAt = new Date('2026-10-21T00:00:00Z');
      await seedDemo(admin,seededAt);
      now = Timestamp.fromDate(new Date('2026-10-21T00:05:00Z'));
      assert.deepEqual(await internal('saveElderSettings',examples.saveElderSettings.input),examples.saveElderSettings.response);
      now = Timestamp.fromDate(new Date('2026-10-21T00:06:00Z'));
      assert.deepEqual(await internal('submitCheckIn',examples.submitCheckIn.input),examples.submitCheckIn.response);
      now = Timestamp.fromDate(new Date('2026-10-21T00:07:00Z'));
      assert.deepEqual(await internal('recordPhoneResponse',examples.recordPhoneResponse.input,'coordinator_demo'),examples.recordPhoneResponse.response);
      await seedDemo(admin,seededAt);
      now = Timestamp.fromDate(new Date('2026-10-21T00:05:00Z'));
      assert.deepEqual(await internal('saveElderSettings',examples.pauseToday.input),examples.pauseToday.response);
      const pausedStatus = (await db.doc('dailyStatuses/elder_demo_2026-10-21').get()).data();
      assert.deepEqual({id:'elder_demo_2026-10-21',...wire(pausedStatus)},examples.pauseToday.unsubmittedDailyStatus);
    });
    await t.test('a new Malaysian day creates its own record while the same intent replays the original day', async () => {
      now = Timestamp.fromDate(new Date('2026-12-31T15:59:59Z'));
      await seedDemo(admin);
      await internal('saveElderSettings',settingsInput({pauseToday:true}));
      assert.equal((await db.doc('elderSettings/elder_demo').get()).data().pausedOn,'2026-12-31');
      now = Timestamp.fromDate(new Date('2026-12-31T16:00:00Z'));
      const input = command();
      const first = await internal('submitCheckIn',input);
      assert.equal(first.data.checkin.localDate,'2027-01-01');
      now = Timestamp.fromDate(new Date('2027-01-01T16:00:00Z'));
      // Replay uses its original result; a fresh intent belongs to the new day.
      assert.deepEqual(await internal('submitCheckIn',input),first);
      const nextDay = await internal('submitCheckIn',command());
      assert.equal(nextDay.data.checkin.localDate,'2027-01-02');
      assert.equal((await db.doc('checkins/elder_demo_2026-12-31').get()).data().state,'paused');
    });
    await t.test('late submission preserves already-created missed-alert history', async () => {
      now = Timestamp.fromDate(new Date('2026-12-31T03:00:00Z'));
      await db.doc('checkins/elder_demo_2026-12-31').delete();
      await internal('saveElderSettings',settingsInput());
      assert.equal((await db.doc('checkins/elder_demo_2026-12-31').get()).data().state,'missed');
      const alert = {recipientUid:'family_demo',elderId:'elder_demo',kind:'checkin_missed',entityId:'elder_demo_2026-12-31',
        consentScope:'daily_sharing',messageParams:{localDate:'2026-12-31'},readAt:null,createdAt:now};
      await db.doc('notifications/stage2_missed_history').set(alert);
      const result = await internal('submitCheckIn',command());
      assert.equal(result.data.checkin.state,'ok');
      assert.deepEqual((await db.doc('notifications/stage2_missed_history').get()).data(),alert);
    });
    await t.test('missing settings reject without partial status or success receipt', async () => {
      await db.doc('elderSettings/elder_demo').delete();
      const input = command();
      const before = (await db.doc('checkins/elder_demo_2026-12-31').get()).data();
      await assert.rejects(internal('submitCheckIn',input),reason('SETTINGS_NOT_CONFIGURED'));
      assert.deepEqual((await db.doc('checkins/elder_demo_2026-12-31').get()).data(),before);
      assert.equal((await db.doc(`commandReceipts/${tupleId('elder_demo','submitCheckIn',input.idempotencyKey)}`).get()).exists,false);
    });
    await t.test('reset removes demo check-ins and receipts across dates while preserving other elders and command types', async () => {
      await db.doc('checkins/stage2_external').set({elderId:'external_elder',localDate:'2026-12-31',state:'pending'});
      await db.doc('dailyStatuses/stage2_external').set({elderId:'external_elder',localDate:'2026-12-31',state:'pending'});
      await db.doc('commandReceipts/stage2_future_command').set({actorUid:'elder_demo',functionName:'futureDomainCommand'});
      await resetDemo(admin);
      for (const date of dates) {
        assert.equal((await db.doc(`checkins/elder_demo_${date}`).get()).exists,false);
        assert.equal((await db.doc(`dailyStatuses/elder_demo_${date}`).get()).exists,false);
      }
      for (const receiptId of receiptIds) assert.equal((await db.doc(`commandReceipts/${receiptId}`).get()).exists,false);
      assert.equal((await db.doc('checkins/stage2_external').get()).exists,true);
      assert.equal((await db.doc('dailyStatuses/stage2_external').get()).exists,true);
      assert.equal((await db.doc('commandReceipts/stage2_future_command').get()).exists,true);
      await seedDemo(admin);
    });
  } finally {
    for (const path of ['notifications/stage2_missed_history','checkins/stage2_external','dailyStatuses/stage2_external',
      'commandReceipts/stage2_future_command']) await db.doc(path).delete();
    for (const date of dates) for (const name of ['checkins','dailyStatuses']) await db.doc(`${name}/elder_demo_${date}`).delete();
    for (const receiptId of receiptIds) await db.doc(`commandReceipts/${receiptId}`).delete();
    await seedDemo(admin);
    await db.terminate();
    await deleteAdminApp(admin.app);
  }
});
