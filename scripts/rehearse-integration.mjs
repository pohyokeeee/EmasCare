import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {integrationClients,requireIntegrationEmulators,command,rehearsalIds} from './integration-client.mjs';
import {checkIntegration,verifyWallet,saveIntegrationReport} from './check-integration.mjs';

// Mutation keys are stable per rehearsal participation/purchase. Re-running this
// script cannot turn retries into another credit or another voucher purchase.
export async function rehearseIntegration(client){
  const steps=[],step=async(name,run)=>{const result=await run();steps.push(name);console.log(`PASS: ${name}`);return result;};
  const runKey=crypto.randomUUID(),key=(s)=>`integration-v1-${s}`;
  const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuala_Lumpur',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  const original=await client.read('elder_demo','elderSettings/elder_demo');
  assert(original,'Run npm.cmd run demo:prepare first');
  assert(original.familySharingEnabled===true&&original.familyBookingEnabled===true,'Enable both permissions as the elder in the UI before rehearsing; the script will not grant withdrawn consent');
  await step('Check-in submission is saved and repeatable',async()=>{
    const input=command(key(`checkin-${today}`));const first=await client.call('elder_demo','submitCheckIn',input),repeat=await client.call('elder_demo','submitCheckIn',input);
    assert.deepEqual(repeat,first);assert.equal(first.checkin.state,'ok');
  });
  await step('Coordinator due processing is repeatable and keeps warnings for review',async()=>{
    const input=command(`integration-due-${runKey}`),first=await client.call('coordinator_demo','processDemoDueItems',input);
    assert.equal(first.warningsCleared,0);assert.deepEqual(await client.call('coordinator_demo','processDemoDueItems',input),first);
  });
  const completions=[];
  for(const requestId of rehearsalIds)await step(`Separate confirmations and 20-coin credits: ${requestId}`,async()=>{
    let r=await client.read('elder_demo',`requests/${requestId}`);assert(r,'Run demo:prepare to create the uncompleted assigned fixtures');
    for(const [state,action]of [['assigned','accept'],['accepted','start'],['in_progress','finish']]){
      if(r.state===state)({request:r}=await client.call('helper_demo','transitionRequest',command(key(`${requestId}-${action}`),{requestId,action})));
    }
    if(r.state==='awaiting_confirmation'){
      if(!r.helperConfirmation)({request:r}=await client.call('helper_demo','transitionRequest',command(key(`${requestId}-helper-confirm`),{requestId,action:'confirm'})));
      if(!r.elderConfirmation)({request:r}=await client.call('elder_demo','transitionRequest',command(key(`${requestId}-elder-confirm`),{requestId,action:'confirm'})));
    }
    assert.equal(r.state,'completed','A cancelled/blocked fixture needs operator review; no source state was overridden');
    const before=await verifyWallet(client,'elder_demo');
    await client.call('elder_demo','transitionRequest',command(key(`${requestId}-confirm-retry`),{requestId,action:'confirm'}));
    assert.deepEqual(await verifyWallet(client,'elder_demo'),before);
    for(const [role,uid]of [['elder','elder_demo'],['helper','helper_demo']]){
      const claim=await client.read(uid,`rewardClaims/${r.participationIds[role]}`);
      assert.equal(claim.status,'credited');assert.equal(claim.amountCoins,20);
    }
    completions.push({requestId,participationIds:r.participationIds});
  });
  const attendance=await step('Standalone activity earns one elder credit through coordinator verification',async()=>{
    let {attendance:a}=await client.call('elder_demo','submitActivityAttendance',command(key('standalone-submit'),{activityId:'activity_demo_attendance'}));
    if(a.status==='submitted')({attendance:a}=await client.call('coordinator_demo','reviewActivityAttendance',command(key('standalone-verify'),{
      attendanceId:a.id,decision:'verify',verificationMethod:'organizer_roster',note:'Synthetic integration rehearsal: coordinator confirms the seeded ended demo activity attendance.'})));
    assert.equal(a.status,'verified');const claim=await client.read('elder_demo',`rewardClaims/${a.participationId}`);assert.equal(claim.amountCoins,20);return a;
  });
  await step('Sharing consent gates cheers, progress and notifications independently of booking',async()=>{
    const first=await client.call('family_demo','sendFamilyCheer',command(key('cheer'),{participationId:attendance.participationId}));
    assert.deepEqual(await client.call('family_demo','sendFamilyCheer',command(key('cheer-another-tap'),{participationId:attendance.participationId})),first);
    const settings=(await client.read('elder_demo','elderSettings/elder_demo'));
    const localDate=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kuala_Lumpur',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
    const input={familySharingEnabled:settings.familySharingEnabled,familyBookingEnabled:settings.familyBookingEnabled,dueLocalTime:settings.dueLocalTime,
      graceMinutes:settings.graceMinutes,pauseToday:settings.pausedOn===localDate};
    const notifications=await client.list('family_demo','notifications',[['recipientUid','family_demo'],['elderId','elder_demo'],['consentScope','daily_sharing']],'createdAt');
    const readInput=notifications[0]?command(key(`notification-${notifications[0].id}`),{notificationId:notifications[0].id}):null;
    if(readInput)await client.call('family_demo','markNotificationRead',readInput);
    try{
      await client.call('elder_demo','saveElderSettings',command(`integration-revoke-${runKey}`,{...input,familySharingEnabled:false}));
      await assert.rejects(client.call('family_demo','getProgress',{contractVersion:1,scope:'elder',entityId:'elder_demo',periodType:'week',periodKey:null}),e=>e.details?.reason==='CONSENT_REQUIRED');
      if(readInput)await assert.rejects(client.call('family_demo','markNotificationRead',readInput),e=>e.details?.reason==='CONSENT_REQUIRED');
      assert(await client.read('family_demo','requests/request_demo_ready'),'Booking visibility stays available under its separate current consent');
    }finally{await client.call('elder_demo','saveElderSettings',command(`integration-restore-${runKey}`,input));}
  });
  await step('Owner wallets redeem earned coins once; retries reuse the persisted voucher',async()=>{
    for(const uid of ['elder_demo','helper_demo']){
      const input=command(key(`voucher-${uid}`),{voucherId:'voucher_demo'});
      const first=await client.call(uid,'redeemDemoVoucher',input);assert.equal(first.redemption.isDemo,true);assert.equal(first.redemption.costCoins,100);
      const saved=await verifyWallet(client,uid);assert.deepEqual(await client.call(uid,'redeemDemoVoucher',input),first);
      assert.deepEqual(await verifyWallet(client,uid),saved);
    }
    await assert.rejects(client.call('family_demo','redeemDemoVoucher',command(key('family-cannot-spend'),{voucherId:'voucher_demo'})),e=>e.details?.reason==='ROLE_NOT_ALLOWED');
  });
  await step('Place report reaches terminal review and warnings stay explicitly coordinator-managed',async()=>{
    const {report}=await client.call('elder_demo','submitReport',command(key('place-report'),{kind:'place_problem',placeId:'place_hall',requestId:null,helperId:null,text:'Synthetic rehearsal: please inspect the hall ramp.'}));
    if(report.state!=='done'){
      await client.call('coordinator_demo','reviewReport',command(key('report-seen'),{reportId:report.id,state:'seen'}));
      await client.call('coordinator_demo','reviewReport',command(key('report-done'),{reportId:report.id,state:'done'}));
    }
    const {place}=await client.call('coordinator_demo','setPlaceWarning',command(`integration-warning-${runKey}`,{placeId:'place_hall',warning:{level:'warning',text:'Synthetic rehearsal: ramp access needs coordinator review.',expiresAt:new Date(Date.now()+3600000).toISOString()}}));
    assert.equal(place.liveStatus.level,'warning');
  });
  await step('Coordinator block is saved for the separate solo-elder scenario',async()=>{
    const result=await client.call('coordinator_demo','blockHelper',command(key('solo-helper-block'),{elderId:'elder_solo',helperId:'helper_demo',reason:'Synthetic separate blocking scenario; main elder pairing stays available.'}));
    assert.deepEqual(result,{elderId:'elder_solo',helperId:'helper_demo',blocked:true});
  });
  const readiness=await checkIntegration(client);
  return {...readiness,steps,completedRequests:completions,standaloneAttendanceId:attendance.id,policyId:'owner-20-all-v1',
    note:'API rehearsal on synthetic local demo participants. No Flutter screens, microphone capture, live provider calls or cloud deployment were verified.'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  assert.equal(process.argv.length,2,'API rehearsal accepts no project, owner, rate, reset or provider arguments');
  await requireIntegrationEmulators();const client=await integrationClients();
  try{const report=await rehearseIntegration(client);await saveIntegrationReport('integration-rehearsal.json',report);console.log(`PASS: ${report.steps.length} journey steps and ${report.checks.length} readiness checks. Results: .cache/integration-rehearsal.json`);}
  finally{await client.close();}
}
