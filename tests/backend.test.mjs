import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {deleteApp} from 'firebase-admin/app';
import {demoClients, seedDemo, resetDemo} from '../scripts/demo.mjs';
import {demoAccounts, demoPassword, townshipId} from '../scripts/fixtures.mjs';
import {projectId, region} from '../scripts/local.mjs';

const require = createRequire(import.meta.url);
const {tupleId, runCommand} = require('../functions/lib/commands.js');
const executeFile = promisify(execFile);
const endpoint = `http://127.0.0.1:5001/${projectId}/${region}`;
async function signIn(email) {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-demo-key', {
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({email,password:demoPassword,returnSecureToken:true}),signal:AbortSignal.timeout(15000),
  });
  const body = await response.json();
  assert.equal(response.status,200,JSON.stringify(body));
  return body.idToken;
}
async function call(name, data, token) {
  const response = await fetch(`${endpoint}/${name}`, {
    method:'POST', headers:{'Content-Type':'application/json',...(token ? {Authorization:`Bearer ${token}`} : {})},
    body:JSON.stringify({data}),signal:AbortSignal.timeout(45000),
  });
  const body = await response.json();
  return {status:response.status,body};
}
function denied(result, reason, status = 403) {
  assert.equal(result.status,status,JSON.stringify(result.body));
  assert.equal(result.body.error.details.reason,reason);
}
const probe = (key,note = 'foundation check',extra = {}) => ({contractVersion:1,idempotencyKey:key,townshipId,note,...extra});

test('authenticated backend foundation against real local emulators', {timeout:180000}, async (t) => {
  const clients = await demoClients();
  const {db,auth} = clients;
  try {
    await resetDemo(clients);
    await seedDemo(clients);
    const tokens = {};
    await t.test('all four roles and standalone/unrelated accounts actually sign in and call the backend', async () => {
      for (const account of demoAccounts) {
        tokens[account.uid] = await signIn(account.email);
        const result = await call('getBackendContext',{contractVersion:1},tokens[account.uid]);
        assert.equal(result.status,200,JSON.stringify(result.body));
        assert.deepEqual(result.body.result,{contractVersion:1,data:{profile:{uid:account.uid,displayName:account.displayName,
          role:account.role,townshipId,householdId:account.householdId,locale:'en'}}});
      }
    });
    await t.test('unauthenticated, malformed and client-supplied role requests fail', async () => {
      denied(await call('getBackendContext',{contractVersion:1}),'AUTH_REQUIRED',401);
      denied(await call('getBackendContext',{contractVersion:9},tokens.elder_demo),'UNSUPPORTED_CONTRACT_VERSION',400);
      denied(await call('getBackendContext',{contractVersion:1,role:'coordinator'},tokens.helper_demo),'UNKNOWN_FIELD',400);
      denied(await call('foundationProbe',probe('role-denied'),tokens.helper_demo),'ROLE_NOT_ALLOWED');
      denied(await call('foundationProbe',probe('town-denied','check',{townshipId:'other'}),tokens.coordinator_demo),'TOWNSHIP_NOT_ALLOWED');
    });
    await t.test('profile deletion blocks access and token role claims never override server-owned role', async () => {
      const profile = (await db.doc('users/helper_demo').get()).data();
      await db.doc('users/helper_demo').delete();
      try { denied(await call('getBackendContext',{contractVersion:1},tokens.helper_demo),'PROFILE_REQUIRED'); }
      finally { await db.doc('users/helper_demo').set(profile); }
      await auth.setCustomUserClaims('helper_demo',{role:'coordinator'});
      const claimed = await signIn('helper@emascare.test');
      try { denied(await call('foundationProbe',probe('claims-denied'),claimed),'ROLE_NOT_ALLOWED'); }
      finally { await auth.setCustomUserClaims('helper_demo',null); }
    });
    await t.test('concurrent retries persist one effect and return one original result', async () => {
      const results = await Promise.all(Array.from({length:5},() => call('foundationProbe',probe('concurrent-once'),tokens.coordinator_demo)));
      for (const result of results) {
        assert.equal(result.status,200,JSON.stringify(result.body));
        assert.deepEqual(result.body,results[0].body);
      }
      assert.equal((await db.doc('foundationProbes/coordinator_demo').get()).data().count,1);
      const receipt = await db.doc(`commandReceipts/${tupleId('coordinator_demo','foundationProbe','concurrent-once')}`).get();
      assert.deepEqual(receipt.data().result,results[0].body.result);
      denied(await call('foundationProbe',probe('concurrent-once','changed intent'),tokens.coordinator_demo),'IDEMPOTENCY_KEY_REUSED',409);
      assert.equal((await db.doc('foundationProbes/coordinator_demo').get()).data().count,1);
    });
    await t.test('current role is rechecked before returning a previously successful receipt', async () => {
      const ref = db.doc('users/coordinator_demo');
      await ref.update({role:'helper'});
      try { denied(await call('foundationProbe',probe('concurrent-once'),tokens.coordinator_demo),'ROLE_NOT_ALLOWED'); }
      finally { await ref.update({role:'coordinator'}); }
    });
    await t.test('an exception rolls back both the mutation and its receipt', async () => {
      const receiptId = tupleId('coordinator_demo','foundationRollbackTest','rollback');
      try {
        await assert.rejects(runCommand({db,uid:'coordinator_demo',name:'foundationRollbackTest',key:'rollback',payload:{intent:'fail'},
          authorize:async () => {},execute:async (tx) => {
            tx.set(db.doc('foundationTestSentinels/rollback'),{mustNotExist:true});
            throw new Error('deliberate test failure');
          }}),/deliberate test failure/);
        assert.equal((await db.doc('foundationTestSentinels/rollback').get()).exists,false);
        assert.equal((await db.doc(`commandReceipts/${receiptId}`).get()).exists,false);
      } finally {
        await db.doc('foundationTestSentinels/rollback').delete();
        await db.doc(`commandReceipts/${receiptId}`).delete();
      }
    });
    await t.test('family permissions are separate, related, current and rechecked on receipt replay', async () => {
      const extra = {elderId:'elder_demo',consentScope:'daily_sharing'};
      const input = probe('concurrent-once','family check',extra);
      assert.equal((await call('foundationProbe',input,tokens.family_demo)).status,200);
      assert.equal((await db.doc('foundationProbes/family_demo').get()).data().count,1);
      denied(await call('foundationProbe',input,tokens.family_unrelated),'UNRELATED_HOUSEHOLD');
      const settings = db.doc('elderSettings/elder_demo');
      await settings.update({familySharingEnabled:false});
      try {
        denied(await call('foundationProbe',input,tokens.family_demo),'CONSENT_REQUIRED');
        const booking = probe('booking-consent','booking check',{elderId:'elder_demo',consentScope:'family_booking'});
        assert.equal((await call('foundationProbe',booking,tokens.family_demo)).status,200);
        await settings.update({familyBookingEnabled:false});
        denied(await call('foundationProbe',booking,tokens.family_demo),'CONSENT_REQUIRED');
      } finally { await settings.update({familySharingEnabled:true,familyBookingEnabled:true}); }
    });
    await t.test('guarded reset restores only known fixtures and preserves unrelated documents and Auth accounts', async () => {
      await db.doc('foundationTestSentinels/keep').set({preserved:true});
      await db.doc('commandReceipts/foundation-test-keep').set({actorUid:'coordinator_demo',functionName:'futureDomainCommand',result:{keep:true}});
      await auth.createUser({uid:'foundation_test_external',email:'external@emascare.test',password:demoPassword});
      await db.doc('wallets/elder_demo').update({balance:999});
      const reset = await executeFile(process.execPath,['scripts/demo.mjs','reset'],{env:process.env,timeout:30000});
      assert.match(reset.stdout,/Reset and reseeded 6 emulator accounts/);
      const seed = await executeFile(process.execPath,['scripts/demo.mjs','seed'],{env:process.env,timeout:30000});
      assert.match(seed.stdout,/Seeded 6 emulator accounts/);
      await assert.rejects(executeFile(process.execPath,['scripts/demo.mjs','reset'],{
        env:{...process.env,GCLOUD_PROJECT:'live-project'},timeout:10000,
      }),(error) => error.code !== 0 && /Refusing non-demo/.test(error.stderr));
      assert.equal((await db.doc('wallets/elder_demo').get()).data().balance,0);
      assert.equal((await db.doc('wallets/helper_demo').get()).data().balance,0);
      assert.equal((await db.doc('foundationProbes/coordinator_demo').get()).exists,false);
      assert.equal((await db.doc(`commandReceipts/${tupleId('coordinator_demo','foundationProbe','concurrent-once')}`).get()).exists,false);
      assert.equal((await db.doc('foundationTestSentinels/keep').get()).data().preserved,true);
      assert.equal((await db.doc('commandReceipts/foundation-test-keep').get()).exists,true);
      assert.equal((await auth.getUser('foundation_test_external')).uid,'foundation_test_external');
      assert.ok(await signIn('elder@emascare.test'));
    });
  } finally {
    await db.doc('foundationTestSentinels/keep').delete();
    await db.doc('commandReceipts/foundation-test-keep').delete();
    await auth.deleteUser('foundation_test_external').catch((error) => { if (error.code !== 'auth/user-not-found') throw error; });
    await db.terminate();
    await deleteApp(clients.app);
  }
});
