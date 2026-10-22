import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {Timestamp} from 'firebase-admin/firestore';
import {loadApprovedDemoPolicy, configureDemoRewards} from '../scripts/configure-rewards.mjs';

const require = createRequire(import.meta.url);
const {evaluatePolicy} = require('../functions/lib/rewards.js');
const execute = promisify(execFile);

test('owner-approved policy credits exactly 20 for every supported action and recipient role, including earlier participation', async () => {
  const {policyId, policy} = await loadApprovedDemoPolicy();
  assert.equal(policyId, 'owner-20-all-v1');
  assert.equal(policy.approvedBy, 'project-owner');
  assert.match(policy.approvalReference, /20 coins/);
  assert(policy.approvedAt instanceof Timestamp);
  for (const role of ['elder','helper']) {
    for (const action of ['activity_attendance','walk_with_me','sit_with_me','carry_light_item','phone_help']) {
      for (const at of ['2026-10-20T00:00:00Z','2026-10-23T00:00:00Z']) {
        const decision = evaluatePolicy(policy, {townshipId:'township_demo', role, action, verifiedAt:Timestamp.fromDate(new Date(at))});
        assert.equal(decision.status, 'credited');
        assert.equal(decision.amountCoins, 20);
        assert.equal(decision.rateCoins, 20);
        assert.equal(decision.ruleVersion, policyId);
      }
    }
  }
  assert.equal(evaluatePolicy(policy, {townshipId:'township_demo',role:'elder',action:'checkin',verifiedAt:Timestamp.now()}).status, 'pending_policy');
});

test('configuration rejects foreign Admin clients before any transaction', async () => {
  let touched = false;
  await assert.rejects(configureDemoRewards({db:{projectId:'live-project',runTransaction:()=>{touched=true;}},auth:{app:{options:{projectId:'live-project'}}}}), /Refusing non-demo/);
  assert.equal(touched, false);
});

test('configuration CLI rejects custom values and live projects before connecting', async () => {
  await assert.rejects(execute(process.execPath, ['scripts/configure-rewards.mjs','--rate=999']), e => /accepts no rates/.test(e.stderr));
  await assert.rejects(execute(process.execPath, ['scripts/configure-rewards.mjs'], {env:{...process.env,GCLOUD_PROJECT:'live-project'}}), e => /Refusing non-demo/.test(e.stderr));
});

test('configuration preserves a different active policy and immutable approved version without writing', async () => {
  const {policyId,policy}=await loadApprovedDemoPolicy();
  for(const [active,existing,expected] of [
    ['newer-policy',undefined,/different reward policy/],
    [policyId,{...policy,rules:policy.rules.map(r=>({...r,rateCoins:40}))},/immutable/],
  ]){
    let writes=0;
    const transaction={
      get:async ref=>ref.path.startsWith('rewardPolicies/')
        ? {data:()=>({townshipId:policy.townshipId,activeVersionId:active})}
        : {exists:existing!==undefined,data:()=>existing},
      create:()=>{writes++;},set:()=>{writes++;},
    };
    const clients={db:{projectId:'demo-emascare',doc:path=>({path}),runTransaction:fn=>fn(transaction)},auth:{app:{options:{projectId:'demo-emascare'}}}};
    await assert.rejects(configureDemoRewards(clients),expected);
    assert.equal(writes,0);
  }
});
