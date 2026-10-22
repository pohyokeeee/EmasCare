import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {integrationClients,requireIntegrationEmulators} from './integration-client.mjs';
import {demoAccounts,townshipId} from './fixtures.mjs';

export async function saveIntegrationReport(name,report){
  const folder=new URL('../.cache/',import.meta.url);await mkdir(folder,{recursive:true});
  await writeFile(new URL(name,folder),JSON.stringify(report,null,2)+'\n');
}
export async function verifyWallet(client,uid){
  const wallet=await client.read(uid,`wallets/${uid}`),filter=[['ownerUid',uid],['townshipId',townshipId]];
  const entries=await client.list(uid,`wallets/${uid}/entries`,filter,'createdAt');
  const claims=await client.list(uid,'rewardClaims',[['beneficiaryUid',uid],['townshipId',townshipId]],'verifiedAt');
  const redemptions=await client.list(uid,'redemptions',filter,'issuedAt');
  assert(wallet&&wallet.ownerUid===uid&&wallet.townshipId===townshipId,'Own wallet scope');
  assert(Number.isSafeInteger(wallet.balance)&&wallet.balance>=0,'Nonnegative integer wallet balance');
  assert(entries.every(e=>['completion_reward','voucher_redemption'].includes(e.type)),'Known ledger entry types');
  assert.equal(wallet.balance,entries.reduce((sum,e)=>sum+e.amount,0),'Wallet must equal its immutable ledger');
  const credits=entries.filter(e=>e.type==='completion_reward'),debits=entries.filter(e=>e.type==='voucher_redemption');
  assert.equal(new Set(credits.map(e=>e.participationId)).size,credits.length,'No duplicate participation credits');
  for(const entry of credits){
    assert.equal(entry.amount,20,'Approved reward amount');assert.equal(entry.rateCoins,20);assert.equal(entry.ruleVersion,'owner-20-all-v1');
    assert(claims.some(c=>c.participationId===entry.participationId&&c.status==='credited'&&c.ledgerEntryId===entry.id&&c.amountCoins===20),'Credit has its owner-visible claim');
  }
  for(const entry of debits)assert.equal(entry.amount,-100,'Backend voucher price');
  assert.equal(debits.length,redemptions.length,'One debit per redemption');
  for(const r of redemptions)assert(r.isDemo===true&&r.costCoins===100&&r.code.startsWith('DEMO-')&&debits.some(e=>e.referenceId===r.id),'Persisted mock voucher/debit pair');
  return {balance:wallet.balance,credits:credits.length,redemptions:redemptions.length};
}

export async function checkIntegration(client){
  const checks=[],check=async(name,run)=>{await run();checks.push(name);};
  for(const a of demoAccounts)await check(`Authenticated ${a.role}: ${a.uid}`,async()=>{
    const {profile}=await client.call(a.uid,'getBackendContext');assert.equal(profile.uid,a.uid);assert.equal(profile.role,a.role);assert.equal(profile.townshipId,townshipId);
  });
  const wallets={};
  for(const uid of ['elder_demo','elder_solo','helper_demo'])await check(`Wallet/ledger consistency: ${uid}`,async()=>{wallets[uid]=await verifyWallet(client,uid);});
  await check('Family cannot read an elder wallet or a broad reward query',async()=>{
    await assert.rejects(client.read('family_demo','wallets/elder_demo'),{code:'permission-denied'});
    await assert.rejects(client.list('family_demo','rewardClaims'),{code:'permission-denied'});
  });
  await check('Unrelated family cannot read elder progress',()=>assert.rejects(client.call('family_unrelated','getProgress',{
    contractVersion:1,scope:'elder',entityId:'elder_demo',periodType:'week',periodKey:null}),e=>e.details?.reason==='UNRELATED_HOUSEHOLD'));
  let elderProgress,helperProgress;
  await check('Own elder/helper progress uses the shared envelope',async()=>{
    ({progress:elderProgress}=await client.call('elder_demo','getProgress',{contractVersion:1,scope:'elder',entityId:'elder_demo',periodType:'week',periodKey:null}));
    ({progress:helperProgress}=await client.call('helper_demo','getProgress',{contractVersion:1,scope:'helper',entityId:'helper_demo',periodType:'week',periodKey:null}));
    assert.equal(elderProgress.targets.outings,2);assert.equal(helperProgress.scope,'helper');
  });
  await check('Availability suppresses small synthetic cohorts and exposes no membership',async()=>{
    const {availabilitySummary:s}=await client.call('elder_demo','getAvailabilitySummary');assert.equal(s.isDemo,true);
    for(const cell of s.cells){assert(!Object.hasOwn(cell,'helperIds')&&!Object.hasOwn(cell,'requestIds'));if(cell.suppressed){assert.equal(cell.helperCount,null);assert.equal(cell.requestCount,null);}else assert(cell.helperCount>=5);}
    await assert.rejects(client.read('coordinator_demo',`availabilityDemoInputs/${townshipId}`),{code:'permission-denied'});
  });
  await check('Coordinator summary is role protected',async()=>{
    const {summary}=await client.call('coordinator_demo','getCoordinatorSummary');assert.equal(summary.townshipId,townshipId);
    await assert.rejects(client.call('elder_demo','getCoordinatorSummary'),e=>e.details?.reason==='ROLE_NOT_ALLOWED');
  });
  return {checkedAt:new Date().toISOString(),projectId:'demo-emascare',status:'passed',checks,wallets,
    progress:{elder:elderProgress,helper:helperProgress},pending:['Connected Flutter Stage 6 screen walkthrough','Configured Gemini BM/EN audio and manual fallback in the browser']};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  assert.equal(process.argv.length,2,'Readiness verification accepts no project or account arguments');
  await requireIntegrationEmulators();const client=await integrationClients();
  try{const report=await checkIntegration(client);await saveIntegrationReport('integration-readiness.json',report);console.log(`PASS: ${report.checks.length} read-only integration checks. Results: .cache/integration-readiness.json`);}
  finally{await client.close();}
}
