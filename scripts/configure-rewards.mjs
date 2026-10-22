// Apply the owner's reviewed, versioned configuration to local demo data only.
// This is not a grant endpoint and never writes a balance, claim or ledger.
import {readFile} from 'node:fs/promises';
import {isDeepStrictEqual} from 'node:util';
import {pathToFileURL} from 'node:url';
import {Timestamp} from 'firebase-admin/firestore';
import {demoClients} from './demo.mjs';
import {localEnvironment, projectId} from './local.mjs';

export async function loadApprovedDemoPolicy() {
  const {policyId, ...policy} = JSON.parse(await readFile(
    new URL('../docs/fixtures/reward_policy_20_coins.json', import.meta.url), 'utf8'));
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(policyId) || policy.townshipId !== 'township_demo' ||
      policy.version !== policyId || policy.status !== 'approved' ||
      !policy.approvedBy?.trim() || !policy.approvalReference?.trim()) {
    throw new Error('Invalid approved demo reward policy');
  }
  for (const name of ['approvedAt', 'effectiveFrom', 'effectiveUntil']) {
    if (name === 'effectiveUntil' && policy[name] === null) continue;
    const date = new Date(policy[name]);
    if (date.toISOString() !== policy[name]) throw new Error(`Invalid policy ${name}`);
    policy[name] = Timestamp.fromDate(date);
  }
  const actions = ['activity_attendance','walk_with_me','sit_with_me','carry_light_item','phone_help'];
  const rules = policy.rules;
  if (!Array.isArray(rules) || rules.length !== 10 || new Set(rules.map(r => r.id)).size !== 10 ||
      actions.some(action => ['elder','helper'].some(role =>
        rules.filter(r => r.action === action && r.role === role && r.eligible === true &&
          r.rateCoins === 20 && typeof r.reason === 'string' && r.reason.length > 0).length !== 1))) {
    throw new Error('The approved demo policy must award 20 coins for all five actions to both roles');
  }
  return {policyId, policy};
}

export async function configureDemoRewards(clients) {
  localEnvironment();
  if (clients.db.projectId !== projectId || clients.auth.app.options.projectId !== projectId) {
    throw new Error('Refusing non-demo Admin clients');
  }
  const {policyId, policy} = await loadApprovedDemoPolicy();
  const versionRef = clients.db.doc(`rewardPolicyVersions/${policyId}`);
  const pointerRef = clients.db.doc(`rewardPolicies/${policy.townshipId}`);
  await clients.db.runTransaction(async tx => {
    const [version, pointer] = await Promise.all([tx.get(versionRef), tx.get(pointerRef)]);
    const before = pointer.data();
    if (before && (before.townshipId !== policy.townshipId ||
        (before.activeVersionId != null && before.activeVersionId !== policyId))) {
      throw new Error('A different reward policy is active; refusing to replace it');
    }
    if (version.exists && !isDeepStrictEqual(version.data(), policy)) {
      throw new Error('An approved policy version is immutable; refusing to overwrite it');
    }
    if (!version.exists) tx.create(versionRef, policy);
    if (before?.activeVersionId !== policyId) {
      tx.set(pointerRef, {townshipId:policy.townshipId, activeVersionId:policyId, updatedAt:Timestamp.now()});
    }
  });
  return {policyId, policy};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 2) throw new Error('This command accepts no rates, recipients, project or policy arguments.');
  const clients = await demoClients(); // exact project/host guard precedes Admin init
  try {
    const {policyId} = await configureDemoRewards(clients);
    console.log(`Active local policy ${policyId}: 20 coins per verified activity/helping session for elders and helpers.`);
  } finally {
    await clients.db.terminate();
    const {deleteApp} = await import('firebase-admin/app');
    await deleteApp(clients.app);
  }
}
