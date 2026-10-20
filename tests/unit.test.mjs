import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {assertLocalEnvironment, localEnvironment, projectId, hosts} from '../scripts/local.mjs';
import {fixtureDocuments, demoAccounts} from '../scripts/fixtures.mjs';

const require = createRequire(import.meta.url);
const {tupleId, payloadHash} = require('../functions/lib/commands.js');
const {inputObject, documentId} = require('../functions/lib/validation.js');
const {authenticatedUid, requireRole, requireTownship} = require('../functions/lib/auth.js');
const reason = (expected) => (error) => error.details?.reason === expected;

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
