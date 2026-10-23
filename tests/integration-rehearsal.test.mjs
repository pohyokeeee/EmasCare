import {test} from 'node:test';
import assert from 'node:assert/strict';
import {deleteApp} from 'firebase-admin/app';
import {demoClients,resetDemo,seedDemo} from '../scripts/demo.mjs';
import {prepareIntegration} from '../scripts/prepare-integration.mjs';
import {integrationClients,rehearsalIds,requireIntegrationEmulators} from '../scripts/integration-client.mjs';
import {checkIntegration} from '../scripts/check-integration.mjs';
import {rehearseIntegration} from '../scripts/rehearse-integration.mjs';

test('Approved-reward API integration rehearsal and non-destructive demo preparation',{timeout:600000},async(t)=>{
  const admin=await demoClients(),{db}=admin;let client;
  const stored=async(path)=>(await db.doc(path).get()).data();
  try{
    await resetDemo(admin);
    await t.test('preflight requires exact local emulators and rejects unavailable services',async()=>{
      await requireIntegrationEmulators();
      await assert.rejects(requireIntegrationEmulators(async()=>{throw new Error('offline');}),/Start the local emulators/);
      await assert.rejects(requireIntegrationEmulators(async()=>new Response(JSON.stringify({auth:{host:'remote',port:9099}}))),/non-loopback/);
    });
    await t.test('fresh setup configures approved rewards and creates only uncompleted assigned fixtures',async()=>{
      const result=await prepareIntegration(admin);assert.equal(result.freshSeed,true);assert.equal(result.assignedFixturesCreated,4);assert.equal(result.policyId,'owner-20-all-v1');
      assert.equal((await db.collection('requests').get()).size,5);assert.equal((await db.collection('participations').get()).size,0);
      for(const id of rehearsalIds){const request=await stored(`requests/${id}`);assert.equal(request.state,'assigned');assert.equal(request.elderConfirmation,null);assert.equal(request.helperConfirmation,null);assert.equal(request.completedAt,null);}
      for(const uid of ['elder_demo','helper_demo']){assert.equal((await stored(`wallets/${uid}`)).balance,0);assert.equal((await db.collection(`wallets/${uid}/entries`).get()).size,0);}
      client=await integrationClients();
    });
    await t.test('preparation reruns preserve settings and existing fixture timestamps instead of reseeding',async()=>{
      const ready=await stored('requests/request_demo_ready'),before=await stored('elderSettings/elder_demo');
      await db.doc('elderSettings/elder_demo').update({familySharingEnabled:false});
      try{
        const result=await prepareIntegration(admin,new Date(Date.now()+60000));assert.equal(result.freshSeed,false);assert.equal(result.assignedFixturesCreated,0);
        assert.deepEqual(await stored('requests/request_demo_ready'),ready);assert.equal((await stored('elderSettings/elder_demo')).familySharingEnabled,false);
      }finally{await db.doc('elderSettings/elder_demo').set(before);}
    });
    await t.test('readiness is read-only across roles and preserves wallets and check-in state',async()=>{
      const before=await stored('checkins/elder_demo_'+new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuala_Lumpur',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));
      const report=await checkIntegration(client);assert.equal(report.status,'passed');assert(report.checks.length>=14);assert.equal(report.wallets.elder_demo.balance,0);
      assert.deepEqual(await stored('checkins/elder_demo_'+new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuala_Lumpur',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())),before);
      assert.equal((await db.collection('commandReceipts').get()).size,0);
    });
    await t.test('real Auth/callable journey creates monthly claims, verifies standalone attendance, consent and coordinator actions',async()=>{
      const report=await rehearseIntegration(client);assert.equal(report.completedRequests.length,5);
      assert.deepEqual(report.wallets.elder_demo,{balance:0,credits:0,demoOpeningCredits:0,redemptions:0});
      assert.deepEqual(report.wallets.helper_demo,{balance:0,credits:0,demoOpeningCredits:0,redemptions:0});
      assert.equal(report.progress.elder.counts.outings,2);assert.equal(report.progress.elder.pendingOutingClassifications,2);
      assert.equal(report.progress.helper.counts.helpingSessions,5);
      assert.equal((await stored('elderSettings/elder_demo')).familySharingEnabled,true);assert.equal((await stored('elderSettings/elder_demo')).familyBookingEnabled,true);
      assert.equal((await db.collection('cheers').get()).size,1);assert.equal((await db.collection('reports').get()).size,1);
      assert.equal((await db.collection('voiceLimits').get()).size,0,'Rehearsal must not invoke the provider or persist parser attempts');
    });
    await t.test('repeating preparation and the whole journey adds no credits, purchases or duplicate cheers/reports',async()=>{
      const before=await checkIntegration(client),settings=await stored('elderSettings/elder_demo'),requests=await Promise.all(rehearsalIds.map(id=>stored(`requests/${id}`)));
      const prepared=await prepareIntegration(admin);assert.equal(prepared.assignedFixturesCreated,0);assert.equal(prepared.reconciled,11);
      assert.deepEqual(await stored('elderSettings/elder_demo'),settings);
      assert.deepEqual(await Promise.all(rehearsalIds.map(id=>stored(`requests/${id}`))),requests);
      const after=await rehearseIntegration(client);assert.deepEqual(after.wallets,before.wallets);
      assert.equal((await db.collection('cheers').get()).size,1);assert.equal((await db.collection('reports').get()).size,1);
    });
    await t.test('partial consent data, a different active policy and orphan ledger history fail without overwriting state',async()=>{
      const before=await stored('wallets/elder_demo'),settings=await stored('elderSettings/elder_demo');
      await db.doc('elderSettings/elder_demo').delete();
      try{await assert.rejects(prepareIntegration(admin),/Missing elderSettings/);assert.deepEqual(await stored('wallets/elder_demo'),before);}
      finally{await db.doc('elderSettings/elder_demo').set(settings);}
      const pointer=await stored('rewardPolicies/township_demo');await db.doc('rewardPolicies/township_demo').update({activeVersionId:'other-approved-policy'});
      try{await assert.rejects(prepareIntegration(admin),/Another reward policy/);assert.deepEqual(await stored('wallets/elder_demo'),before);}
      finally{await db.doc('rewardPolicies/township_demo').set(pointer);}
      await client.close();client=null;await resetDemo(admin);
      const orphan=db.doc('wallets/elder_demo/entries/orphan_test');await orphan.set({ownerUid:'elder_demo',amount:20});
      try{await assert.rejects(prepareIntegration(admin),/ledger history exists/);assert.equal(await stored('users/elder_demo'),undefined);assert.equal((await orphan.get()).exists,true);}
      finally{await orphan.delete();}
    });
  }finally{
    if(client)await client.close();await resetDemo(admin);await seedDemo(admin);await db.terminate();await deleteApp(admin.app);
  }
});
