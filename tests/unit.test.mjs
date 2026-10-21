import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {assertLocalEnvironment, localEnvironment, projectId, hosts} from '../scripts/local.mjs';
import {fixtureDocuments, demoAccounts} from '../scripts/fixtures.mjs';
import {Timestamp} from 'firebase-admin/firestore';

const require = createRequire(import.meta.url);
const {tupleId, payloadHash} = require('../functions/lib/commands.js');
const {inputObject, documentId} = require('../functions/lib/validation.js');
const {authenticatedUid, requireRole, requireTownship} = require('../functions/lib/auth.js');
const {malaysiaDate, dailySchedule, unsubmittedState, createCheckInService} = require('../functions/lib/checkins.js');
const {slotsInput,isoTime,daySegments,covers} = require('../functions/lib/scheduling.js');
const {createSessionService} = require('../functions/lib/sessions.js');
const reason = (expected) => (error) => error.details?.reason === expected;

test('weekly slots cover whole Malaysian intervals, including adjacent slots, midnight and Sunday to Monday', () => {
  const start=isoTime('2026-10-25T15:30:00Z'), end=isoTime('2026-10-25T16:30:00.000Z');
  assert.deepEqual(daySegments(start,end),[
    {localDate:'2026-10-25',weekday:7,startMinute:1410,endMinute:1440},
    {localDate:'2026-10-26',weekday:1,startMinute:0,endMinute:30},
  ]);
  const slots=slotsInput([{weekday:7,startMinute:1380,endMinute:1440},{weekday:1,startMinute:0,endMinute:15},{weekday:1,startMinute:15,endMinute:60}]);
  assert.equal(covers(slots,start,end),true);
  assert.equal(covers(slots.filter((s)=>s.startMinute!==15),start,end),false);
  assert.equal(daySegments(start,isoTime('2026-10-25T16:00:00Z')).length,1);
  for (const value of ['0000-01-01T00:00:00Z','2026-02-30T01:00:00Z','2026-10-25T16:00:01Z','2026-10-25T16:00:00+08:00','invalid',null]) {
    assert.throws(()=>isoTime(value),reason('INVALID_TIME_RANGE'));
  }
  for (const slots of [[{weekday:0,startMinute:0,endMinute:10}],[{weekday:1,startMinute:0,endMinute:0}],
    [{weekday:1,startMinute:0,endMinute:1441}],[{weekday:1,startMinute:0,endMinute:10,approved:true}]]) {
    assert.throws(()=>slotsInput(slots),reason('INVALID_AVAILABILITY'));
  }
});

test('booking rejects forged identities, states, rates and invalid times before touching Firestore', async () => {
  const service=createSessionService({});
  const input={contractVersion:1,idempotencyKey:'validation',elderId:'elder_demo',activityId:null,placeId:'place_garden',
    startsAt:'2026-10-22T01:00:00Z',endsAt:'2026-10-22T02:00:00Z',taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'any'};
  for (const extra of [{helperId:'helper_demo'},{state:'completed'},{amountCoins:100},{completedAt:input.startsAt}]) {
    await assert.rejects(service.createRequest('elder_demo',{...input,...extra}),reason('UNKNOWN_FIELD'));
  }
  for (const endsAt of [input.startsAt,'2026-10-23T02:00:00Z']) await assert.rejects(service.createRequest('elder_demo',{...input,endsAt}),reason('INVALID_TIME_RANGE'));
  await assert.rejects(service.createRequest('elder_demo',{...input,taskType:'unknown'}),reason('INVALID_TASK'));
});

test('local scripts refuse real projects, missing hosts and remote or malformed endpoints', () => {
  const valid = {GCLOUD_PROJECT:projectId,...hosts};
  assert.deepEqual(assertLocalEnvironment(valid), valid);
  assert.equal(localEnvironment({}).GCLOUD_PROJECT, projectId);
  for (const name of ['GCLOUD_PROJECT','GOOGLE_CLOUD_PROJECT','FIREBASE_PROJECT_ID']) {
    assert.throws(() => localEnvironment({...valid,[name]:'live-project'}), /non-demo/);
  }
  for (const name of Object.keys(hosts)) {
    for (const value of [undefined,'','example.com:8080','https://127.0.0.1:8080','127.0.0.1:9999']) {
      assert.throws(() => assertLocalEnvironment({...valid,[name]:value}), /missing or non-local/);
    }
  }
  assert.throws(() => localEnvironment({...valid,FIREBASE_CONFIG:'{"projectId":"live"}'}), /non-demo/);
  assert.throws(() => localEnvironment({...valid,FIREBASE_CONFIG:'/path/to/config'}), /inline JSON/);
});

test('canonical keys separate ambiguous tuples and hashes ignore object field order', () => {
  assert.notEqual(tupleId('ab','c'), tupleId('a','bc'));
  assert.notEqual(tupleId('actor','function','key'), tupleId('actor2','function','key'));
  assert.equal(payloadHash({b:[2,3],a:{z:null,x:'yes'}}), payloadHash({a:{x:'yes',z:null},b:[2,3]}));
  assert.notEqual(payloadHash({a:[1,2]}), payloadHash({a:[2,1]}));
  assert.throws(() => payloadHash({value:undefined}), reason('INVALID_PAYLOAD'));
  assert.throws(() => payloadHash({value:NaN}), reason('INVALID_PAYLOAD'));
});

test('validation rejects role spoofing, bad versions, empty keys and unsafe document IDs', () => {
  assert.throws(() => inputObject({contractVersion:2},[]), reason('UNSUPPORTED_CONTRACT_VERSION'));
  assert.throws(() => inputObject({contractVersion:1,role:'coordinator'},[]), reason('UNKNOWN_FIELD'));
  assert.throws(() => inputObject({contractVersion:1,idempotencyKey:' '},[],true), reason('INVALID_IDEMPOTENCY_KEY'));
  for (const id of ['a/b','..','',null]) assert.throws(() => documentId(id));
  assert.equal(documentId('elder_demo'), 'elder_demo');
  assert.throws(() => authenticatedUid(undefined), reason('AUTH_REQUIRED'));
  const family = {role:'family',townshipId:'township_demo'};
  assert.throws(() => requireRole(family,['coordinator']), reason('ROLE_NOT_ALLOWED'));
  assert.throws(() => requireTownship(family,'other'), reason('TOWNSHIP_NOT_ALLOWED'));
});

test('executable fixtures include standalone elder, both wallets and no invented rewards', () => {
  const docs = fixtureDocuments(new Date('2026-10-21T00:00:00Z'));
  assert.equal(new Set(docs.map((doc) => doc.path)).size, docs.length);
  for (const account of demoAccounts.filter((a) => ['elder','helper'].includes(a.role))) {
    assert.equal(docs.find((d) => d.path === `wallets/${account.uid}`).data.balance,0);
  }
  assert.ok(docs.some((d) => d.path === 'users/elder_solo'));
  assert.ok(!docs.some((d) => d.path.startsWith('rewardClaims/') || d.path.includes('/entries/')));
  assert.equal(docs.find((d) => d.path === 'voucherCatalog/voucher_demo').data.costCoins,100);
  assert.equal(docs.find((d) => d.path === 'activities/activity_garden').data.startsAt.toDate().toISOString(),'2026-10-22T01:00:00.000Z');
});

test('write probe is absent from the non-emulator function exports', () => {
  const saved = process.env.FUNCTIONS_EMULATOR;
  delete process.env.FUNCTIONS_EMULATOR;
  try {
    const functions = require('../functions/lib/index.js');
    assert.equal(typeof functions.getBackendContext,'function');
    assert.equal(functions.foundationProbe,undefined);
  } finally {
    if (saved !== undefined) process.env.FUNCTIONS_EMULATOR = saved;
  }
});

test('check-in dates and due times follow Malaysia at midnight, year rollover and leap day', () => {
  const at = (iso) => Timestamp.fromDate(new Date(iso));
  assert.equal(malaysiaDate(at('2026-12-31T15:59:59.999Z')),'2026-12-31');
  assert.equal(malaysiaDate(at('2026-12-31T16:00:00.000Z')),'2027-01-01');
  assert.equal(malaysiaDate(at('2028-02-28T16:00:00.000Z')),'2028-02-29');
  const day = dailySchedule(at('2026-10-20T16:00:00Z'),'09:00',30);
  assert.equal(day.localDate,'2026-10-21');
  assert.equal(day.dueAt.toDate().toISOString(),'2026-10-21T01:00:00.000Z');
  assert.equal(day.graceEndsAt.toDate().toISOString(),'2026-10-21T01:30:00.000Z');
});

test('pending, reminded, missed and pause boundaries are deterministic', () => {
  const settings = {dueLocalTime:'09:00',graceMinutes:30,pausedOn:null};
  const state = (iso,options = settings) => unsubmittedState(Timestamp.fromDate(new Date(iso)),options);
  assert.equal(state('2026-10-21T00:59:59Z'),'pending');
  assert.equal(state('2026-10-21T01:00:00Z'),'reminded');
  assert.equal(state('2026-10-21T01:29:59Z'),'reminded');
  assert.equal(state('2026-10-21T01:30:00Z'),'missed');
  assert.equal(state('2026-10-21T01:00:00Z',{...settings,graceMinutes:0}),'missed');
  assert.equal(state('2026-10-21T01:30:00Z',{...settings,pausedOn:'2026-10-21'}),'paused');
  assert.notEqual(state('2026-10-21T16:00:00Z',{...settings,pausedOn:'2026-10-21'}),'paused');
});

test('settings validation rejects invalid times, noninteger grace and caller-owned identity/time fields', async () => {
  const service = createCheckInService({});
  const settings = {contractVersion:1,idempotencyKey:'validation',familySharingEnabled:true,familyBookingEnabled:false,
    dueLocalTime:'09:00',graceMinutes:30,pauseToday:false};
  for (const dueLocalTime of ['24:00','9:00','09:60','09:00:00',null]) {
    await assert.rejects(service.saveElderSettings('elder_demo',{...settings,dueLocalTime}),reason('INVALID_DUE_TIME'));
  }
  for (const graceMinutes of [-1,1.5,1441,'30',null]) {
    await assert.rejects(service.saveElderSettings('elder_demo',{...settings,graceMinutes}),reason('INVALID_GRACE_MINUTES'));
  }
  await assert.rejects(service.saveElderSettings('elder_demo',{...settings,pauseToday:'true'}),reason('INVALID_SETTINGS'));
  for (const extra of [{elderId:'other'},{source:'coordinator_phone'},{localDate:'2026-01-01'},{submittedAt:'2026-01-01T00:00:00Z'}]) {
    await assert.rejects(service.submitCheckIn('elder_demo',{contractVersion:1,idempotencyKey:'validation',...extra}),reason('UNKNOWN_FIELD'));
  }
});
