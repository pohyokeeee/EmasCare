import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {demoClients,resetDemo,seedDemo} from '../scripts/demo.mjs';
const require=createRequire(import.meta.url);
const {createOperationsService}=require('../functions/lib/operations.js');
const {createSummaryService}=require('../functions/lib/summaries.js');
const reason=(r)=>(e)=>e.details?.reason===r;

test('Stage 6 report and household-summary permissions use current membership consistently',{timeout:90000},async()=>{
  const admin=await demoClients(),{db}=admin,now=Timestamp.fromDate(new Date('2026-10-22T01:00:00Z'));
  try {
    await resetDemo(admin);await seedDemo(admin,now.toDate());
    const operations=createOperationsService(db,()=>now),summaries=createSummaryService(db,()=>now);
    const report={contractVersion:1,idempotencyKey:'membership-report',kind:'helper_report',text:'Review this pairing.',placeId:null,requestId:'request_demo_ready',helperId:'helper_demo'};
    const result=await operations.submitReport('family_demo',report);assert.equal(result.data.report.state,'new');
    // Elder/family move together; old request still belongs to their former household.
    const old=(await db.doc('households/household_demo').get()).data();
    await db.doc('households/stage6_new_household').set(old);
    await db.doc('users/elder_demo').update({householdId:'stage6_new_household'});
    await db.doc('users/family_demo').update({householdId:'stage6_new_household'});
    await assert.rejects(operations.submitReport('family_demo',report),reason('UNRELATED_HOUSEHOLD'));
    await assert.rejects(operations.submitReport('elder_demo',{...report,idempotencyKey:'elder-moved'}),reason('UNRELATED_HOUSEHOLD'));
    // Coordinator follow-up remains possible; this is not delegated family access.
    assert.equal((await operations.submitReport('coordinator_demo',{...report,idempotencyKey:'coord-review'})).data.report.createdBy,'coordinator_demo');
    const request=(await db.doc('requests/request_demo_ready').get()).data();
    await db.doc('requests/request_demo_ready').set({...request,state:'completed',startsAt:Timestamp.fromDate(new Date('2026-10-17T01:00:00Z')),
      completedAt:now,elderConfirmation:{uid:'elder_demo',at:now},helperConfirmation:{uid:'helper_demo',at:now}});
    const input={contractVersion:1,scope:'household',entityId:'household_helper',periodType:'month',periodKey:null};
    assert.equal((await summaries.getProgress('coordinator_demo',input)).data.progress.counts.weekendGiveBack,2);
    await db.doc('households/household_helper').update({memberUids:[]});
    assert.equal((await summaries.getProgress('coordinator_demo',input)).data.progress.counts.weekendGiveBack,1); // labelled synthetic history only
    await assert.rejects(summaries.getProgress('helper_demo',input),reason('UNRELATED_HOUSEHOLD'));
  } finally {
    await db.doc('households/stage6_new_household').delete();
    await resetDemo(admin);await seedDemo(admin);await db.terminate();await deleteApp(admin.app);
  }
});
