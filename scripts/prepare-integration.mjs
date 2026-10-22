import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {demoClients,seedDemo} from './demo.mjs';
import {demoAccounts,fixtureDocuments,townshipId} from './fixtures.mjs';
import {configureDemoRewards,loadApprovedDemoPolicy} from './configure-rewards.mjs';
import {requireIntegrationEmulators,rehearsalIds} from './integration-client.mjs';
import {localEnvironment,projectId} from './local.mjs';
const require=createRequire(import.meta.url);
const {daySegments}=require('../functions/lib/scheduling.js');
const {reservationId}=require('../functions/lib/sessions.js');
const {reconcileVerifiedParticipation}=require('../functions/lib/reconciliation.js');

export async function prepareIntegration(clients,now=new Date()) {
  localEnvironment();
  assert.equal(clients.db.projectId,projectId,'Refusing non-demo Firestore');
  assert.equal(clients.auth.app.options.projectId,projectId,'Refusing non-demo Auth');
  const {db,auth}=clients,{policyId}=await loadApprovedDemoPolicy();
  const pointer=(await db.doc(`rewardPolicies/${townshipId}`).get()).data();
  assert(!pointer?.activeVersionId||pointer.activeVersionId===policyId,'Another reward policy is active; no integration setup changes were made');
  const profiles=await db.getAll(...demoAccounts.map(a=>db.doc(`users/${a.uid}`)));
  const fresh=profiles.every(p=>!p.exists);
  if(fresh){
    // Refuse a partial financial/domain store, even if its user profiles vanished.
    for(const name of ['requests','participations','wallets','redemptions'])for(const {uid,role}of demoAccounts){
      const field=name==='requests'?'elderId':name==='participations'?'beneficiaryUid':'ownerUid';
      if(name==='requests'&&role!=='elder')continue;
      assert((await db.collection(name).where(field,'==',uid).limit(1).get()).empty,'Demo profiles are missing but domain history exists; setup will not overwrite it');
    }
    for(const {uid,role}of demoAccounts)if(['elder','helper'].includes(role))assert((await db.collection(`wallets/${uid}/entries`).limit(1).get()).empty,
      'Demo profiles are missing but ledger history exists; setup will not overwrite it');
    await seedDemo(clients,now);
  }else{
    for(let i=0;i<demoAccounts.length;i++){
      const account=demoAccounts[i],profile=profiles[i].data();
      assert(profile&&profile.role===account.role&&profile.townshipId===townshipId&&profile.householdId===account.householdId,
        `Demo profile ${account.uid} is missing or changed; existing state was preserved`);
      const user=await auth.getUser(account.uid);assert.equal(user.email,account.email,'Existing demo Auth account does not match');
    }
    // Never reseed an existing store: seedDemo would replace request/settings
    // history. Missing domain/consent/financial records need explicit operator review.
    const required=fixtureDocuments(now).filter(d=>!d.path.startsWith('checkins/')&&!d.path.startsWith('dailyStatuses/')&&!d.path.startsWith('helperReservations/'));
    const snapshots=await db.getAll(...required.map(d=>db.doc(d.path)));
    for(const row of snapshots)assert(row.exists,`Missing ${row.ref.path}; preserve this store or explicitly reset the demo before preparing a clean rehearsal`);
  }
  await configureDemoRewards(clients);
  let reconciled=0;
  for(const {uid,role}of demoAccounts)if(['elder','helper'].includes(role)){
    for(const row of(await db.collection('participations').where('beneficiaryUid','==',uid).get()).docs){
      await reconcileVerifiedParticipation(db,row.id);reconciled++;
    }
  }
  // Four additional ASSIGNED fixtures, with no completion/confirmation/credit.
  // Actual helper/elder callable confirmations are still required to earn.
  const ready=(await db.doc('requests/request_demo_ready').get()).data();
  assert(ready?.elderId==='elder_demo'&&ready.helperId==='helper_demo'&&ready.startsAt instanceof Timestamp,'The ready-session fixture is missing or changed');
  let assignedFixturesCreated=0;
  for(const [index,taskType]of ['walk_with_me','sit_with_me','carry_light_item','phone_help'].entries()){
    const id=rehearsalIds[index+1],start=Timestamp.fromMillis(ready.startsAt.toMillis()-(index+1)*20*60000),end=Timestamp.fromMillis(start.toMillis()+10*60000);
    const created=await db.runTransaction(async tx=>{
      const ref=db.doc(`requests/${id}`),before=await tx.get(ref);
      if(before.exists){
        const d=before.data();assert(d.elderId==='elder_demo'&&d.helperId==='helper_demo'&&d.townshipId===townshipId&&d.taskType===taskType&&d.seedScenario==='integration_rehearsal_v1','Rehearsal ID is already used by another record');return false;
      }
      const segments=daySegments(start,end),refs=segments.map(s=>db.doc(`helperReservations/${reservationId('helper_demo',s.localDate)}`));
      const reservations=await tx.getAll(...refs),at=Timestamp.fromMillis(start.toMillis()-60000);
      for(const row of reservations)for(const slot of row.data()?.slots??[]){
        assert(slot.requestId===id||slot.endsAt.toMillis()<=start.toMillis()||slot.startsAt.toMillis()>=end.toMillis(),'A rehearsal slot overlaps an existing reservation; no booking was replaced');
      }
      tx.create(ref,{...ready,activityId:null,placeId:taskType==='phone_help'?null:'place_hall',startsAt:start,endsAt:end,taskType,state:'assigned',
        acceptedAt:null,startedAt:null,finishedAt:null,elderConfirmation:null,helperConfirmation:null,completedAt:null,cancelledAt:null,
        completionEventId:null,participationIds:{elder:null,helper:null},assignedAt:at,createdAt:at,updatedAt:at,isDemoSeed:true,seededAt:Timestamp.fromDate(now),seedScenario:'integration_rehearsal_v1'});
      reservations.forEach((row,i)=>tx.set(refs[i],{helperId:'helper_demo',townshipId,localDate:segments[i].localDate,
        slots:[...(row.data()?.slots??[]).filter(s=>s.requestId!==id),{requestId:id,startsAt:start,endsAt:end}],updatedAt:at}));
      return true;
    });
    if(created)assignedFixturesCreated++;
  }
  return {projectId,freshSeed:fresh,policyId,assignedFixturesCreated,reconciled,assignedRequestIds:rehearsalIds};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  assert.equal(process.argv.length,2,'Integration preparation accepts no project, recipient, rate or reset arguments');
  await requireIntegrationEmulators();
  const clients=await demoClients();
  try{console.log(JSON.stringify(await prepareIntegration(clients),null,2));console.log('Ready for npm.cmd run demo:rehearse or the teammate UI walkthrough. Existing records were preserved.');}
  finally{await clients.db.terminate();await deleteApp(clients.app);}
}
