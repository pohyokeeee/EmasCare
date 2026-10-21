import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {getFirestore,connectFirestoreEmulator,doc,getDocFromServer,getDocsFromServer,collection,query,where,orderBy,setDoc,updateDoc,deleteDoc,terminate} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';
import {deleteApp as deleteAdminApp} from 'firebase-admin/app';
import {demoClients,seedDemo,resetDemo} from '../scripts/demo.mjs';
import {demoAccounts,demoPassword,townshipId} from '../scripts/fixtures.mjs';
import {projectId,region} from '../scripts/local.mjs';

const require=createRequire(import.meta.url);
const {reconcileVerifiedParticipation}=require('../functions/lib/reconciliation.js');
const {createSessionService}=require('../functions/lib/sessions.js');
const {createWalletService,redemptionId,redemptionEntryId}=require('../functions/lib/wallet.js');
const {rewardEntryId}=require('../functions/lib/rewards.js');
const {completionId,participationId}=require('../functions/lib/completions.js');
const {wireRecord}=require('../functions/lib/scheduling.js');
const {tupleId}=require('../functions/lib/commands.js');
const executeFile=promisify(execFile);
const command=(fields={})=>({contractVersion:1,idempotencyKey:crypto.randomUUID(),...fields});
const reason=(expected)=>(error)=>error.details?.reason===expected;
const policyId='test_stage5_policy';

test('Stage 5 configured rewards, both-role wallets, immutable ledger and protected mock redemption', {timeout:360000},async(t)=>{
  const admin=await demoClients(),{db}=admin,clients=new Map();
  try{
    await resetDemo(admin);await seedDemo(admin);
    for(const account of demoAccounts){
      const app=initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:demo'},crypto.randomUUID());
      const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const firestore=getFirestore(app);connectFirestoreEmulator(firestore,'127.0.0.1',8080);
      const functions=getFunctions(app,region);connectFunctionsEmulator(functions,'127.0.0.1',5001);
      await signInWithEmailAndPassword(auth,account.email,demoPassword);clients.set(account.uid,{app,firestore,functions});
    }
    const call=async(uid,name,input)=>(await httpsCallable(clients.get(uid).functions,name)(input)).data;
    const stored=async(path)=>(await db.doc(path).get()).data();
    const read=(uid,path)=>getDocFromServer(doc(clients.get(uid).firestore,path));
    const redeem=(uid='elder_demo',input=command({voucherId:'voucher_demo'}))=>call(uid,'redeemDemoVoucher',input);
    const balance=async(uid)=>(await stored(`wallets/${uid}`)).balance;
    const entries=async(uid)=>(await db.collection(`wallets/${uid}/entries`).get()).docs;
    // TEST ONLY: derive isolated accounting inputs from the already approved
    // mock voucher price. These are never seeded/approved product earning rates.
    const testAmount=async()=>(await stored('voucherCatalog/voucher_demo')).costCoins;
    const testPolicy=async(rules,extra={})=>{
      const policy={townshipId,version:'test-only-v1',status:'approved',approvedBy:'isolated-emulator-test',
        approvalReference:'SYNTHETIC TEST ONLY; not user approval',approvedAt:Timestamp.now(),effectiveFrom:Timestamp.fromMillis(0),effectiveUntil:null,rules,...extra};
      await db.doc(`rewardPolicyVersions/${policyId}`).set(policy);
      await db.doc(`rewardPolicies/${townshipId}`).set({townshipId,activeVersionId:policyId});return policy;
    };
    const rulesFor=async(action='phone_help')=>{
      const amount=await testAmount();
      return ['elder','helper'].map((role)=>({id:`test-${action}-${role}`,action,role,eligible:true,rateCoins:amount,reason:'SYNTHETIC_TEST_ONLY'}));
    };
    const install=async(action='phone_help')=>{
      const amount=await testAmount(),rules=await rulesFor(action);
      return testPolicy(rules.map((rule)=>({...rule,rateCoins:amount})));
    };
    const finishReady=async()=>{
      for(const action of ['accept','start','finish'])await call('helper_demo','transitionRequest',command({requestId:'request_demo_ready',action}));
      await call('elder_demo','transitionRequest',command({requestId:'request_demo_ready',action:'confirm'}));
      return (await call('helper_demo','transitionRequest',command({requestId:'request_demo_ready',action:'confirm'}))).data.request;
    };
    t.beforeEach(async()=>{await resetDemo(admin);await seedDemo(admin);await db.doc(`rewardPolicyVersions/${policyId}`).delete();});

    await t.test('redemption requires authentication, actual owner role and no client money/recipient fields',async()=>{
      const app=initializeApp({projectId,apiKey:'local-demo-key'},crypto.randomUUID());
      try{const f=getFunctions(app,region);connectFunctionsEmulator(f,'127.0.0.1',5001);
        await assert.rejects(httpsCallable(f,'redeemDemoVoucher')(command({voucherId:'voucher_demo'})),reason('AUTH_REQUIRED'));
      }finally{await deleteApp(app);}
      for(const uid of ['family_demo','family_unrelated','coordinator_demo'])await assert.rejects(redeem(uid),reason('ROLE_NOT_ALLOWED'));
      await assert.rejects(redeem('elder_demo',command({voucherId:'voucher_demo',ownerUid:'helper_demo'})),reason('UNKNOWN_FIELD'));
      assert.equal((await db.collection('redemptions').get()).size,0);
    });

    await t.test('default completion policy stays pending and zero wallets cannot redeem',async()=>{
      const done=await finishReady();
      for(const role of ['elder','helper']){
        const uid=`${role}_demo`,claim=await stored(`rewardClaims/${done.participationIds[role]}`);
        assert.equal(claim.status,'pending_policy');assert.equal(claim.amountCoins,null);assert.equal(await balance(uid),0);
        assert.equal((await entries(uid)).length,0);
        await assert.rejects(redeem(uid),reason('INSUFFICIENT_BALANCE'));
      }
      assert.equal((await db.collection('redemptions').get()).size,0);
      const cli=await executeFile(process.execPath,['scripts/reconcile-rewards.mjs'],{env:process.env,timeout:30000});
      assert.match(cli.stdout,/Reconciled 2 verified demo participations/);assert.match(cli.stdout,/pending_policy/);
      assert.equal(await balance('elder_demo'),0);
      await assert.rejects(executeFile(process.execPath,['scripts/reconcile-rewards.mjs'],{env:{...process.env,GCLOUD_PROJECT:'live-project'},timeout:10000}),
        (error)=>/Refusing non-demo/.test(error.stderr));
    });

    await t.test('both elders and helpers can redeem an isolated sufficient balance; response and ledger fields are exact',async()=>{
      for(const uid of ['elder_demo','helper_demo']){
        await db.doc(`wallets/${uid}`).update({balance:await testAmount()});
        const input=command({voucherId:'voucher_demo'}),result=await redeem(uid,input),id=redemptionId(uid,input.idempotencyKey),entryId=redemptionEntryId(id);
        assert.deepEqual(result,{contractVersion:1,data:{redemption:wireRecord(id,await stored(`redemptions/${id}`)),entryId,balance:0}});
        assert.equal(result.data.redemption.isDemo,true);assert.match(result.data.redemption.code,/^DEMO-/);
        const entry=await stored(`wallets/${uid}/entries/${entryId}`);
        assert.equal(entry.type,'voucher_redemption');assert.equal(entry.amount,-await testAmount());assert.equal(entry.balanceAfter,0);
        assert.equal(entry.referenceId,id);assert.equal(entry.ownerUid,uid);
        for(const field of ['participationId','completionEventId','ruleId','ruleVersion','rateCoins'])assert.equal(entry[field],null);
        assert.deepEqual(await redeem(uid,input),result);assert.equal((await entries(uid)).length,1);
        await assert.rejects(redeem(uid),reason('INSUFFICIENT_BALANCE'));
      }
    });

    await t.test('malformed policy references retain verified completions with pending claims and no credits',async()=>{
      await db.doc(`rewardPolicies/${townshipId}`).set({activeVersionId:'invalid/reference'});
      const done=await finishReady();assert.equal(done.state,'completed');
      for(const role of ['elder','helper']){
        const claim=await stored(`rewardClaims/${done.participationIds[role]}`);
        assert.equal(claim.status,'pending_policy');assert.equal(claim.reason,'REWARD_POLICY_INVALID');assert.equal(claim.amountCoins,null);
        assert.equal(await balance(`${role}_demo`),0);assert.equal((await entries(`${role}_demo`)).length,0);
      }
    });

    await t.test('same-key retries debit once; competing purchases cannot overspend and new funded purchases get new vouchers',async()=>{
      const amount=await testAmount();await db.doc('wallets/elder_demo').update({balance:amount});
      const input=command({voucherId:'voucher_demo'}),results=await Promise.all([redeem('elder_demo',input),redeem('elder_demo',input)]);
      assert.deepEqual(results[0],results[1]);assert.equal(await balance('elder_demo'),0);assert.equal((await entries('elder_demo')).length,1);
      await db.doc('wallets/helper_demo').update({balance:amount});
      const race=await Promise.allSettled([redeem('helper_demo'),redeem('helper_demo')]);
      assert.equal(race.filter((r)=>r.status==='fulfilled').length,1);assert.equal(race.find((r)=>r.status==='rejected').reason.details.reason,'INSUFFICIENT_BALANCE');
      await db.doc('wallets/elder_solo').update({balance:amount*2});
      const purchases=await Promise.all([redeem('elder_solo'),redeem('elder_solo')]);
      assert.notEqual(purchases[0].data.redemption.id,purchases[1].data.redemption.id);assert.notEqual(purchases[0].data.redemption.code,purchases[1].data.redemption.code);
      assert.equal(await balance('elder_solo'),0);assert.equal((await entries('elder_solo')).length,2);
    });

    await t.test('catalog, price and wallet validation failures roll back debit, issuance and receipts',async()=>{
      const ref=db.doc('voucherCatalog/voucher_demo'),catalog=await stored(ref.path);
      await db.doc('wallets/elder_demo').update({balance:await testAmount()});
      for(const [patch,error]of [[{active:false},'VOUCHER_NOT_AVAILABLE'],[{isDemo:false},'VOUCHER_NOT_AVAILABLE'],[{costCoins:1},'INVALID_VOUCHER_PRICE'],[{townshipId:'other'},'TOWNSHIP_NOT_ALLOWED']]){
        await ref.update(patch);const input=command({voucherId:'voucher_demo'});await assert.rejects(redeem('elder_demo',input),reason(error));
        assert.equal((await db.doc(`commandReceipts/${tupleId('elder_demo','redeemDemoVoucher',input.idempotencyKey)}`).get()).exists,false);await ref.set(catalog);
      }
      await assert.rejects(redeem('elder_demo',command({voucherId:'unknown'})),reason('VOUCHER_NOT_FOUND'));
      for(const value of [-1,1.5,Number.MAX_SAFE_INTEGER+1]){await db.doc('wallets/elder_demo').update({balance:value});await assert.rejects(redeem(),reason('INVALID_WALLET_BALANCE'));}
      await db.doc('wallets/elder_demo').update({balance:catalog.costCoins,ownerUid:'helper_demo'});await assert.rejects(redeem(),reason('WALLET_ACCESS_DENIED'));
      assert.equal((await entries('elder_demo')).length,0);assert.equal((await db.collection('redemptions').get()).size,0);
    });

    await t.test('redemption receipt replay rechecks role and wallet scope while retaining the original successful result',async()=>{
      await db.doc('wallets/elder_demo').update({balance:await testAmount()});const input=command({voucherId:'voucher_demo'}),result=await redeem('elder_demo',input);
      await db.doc('voucherCatalog/voucher_demo').update({active:false});assert.deepEqual(await redeem('elder_demo',input),result);
      await assert.rejects(redeem(),reason('VOUCHER_NOT_AVAILABLE'));
      await db.doc('users/elder_demo').update({role:'family'});await assert.rejects(redeem('elder_demo',input),reason('ROLE_NOT_ALLOWED'));
      await db.doc('users/elder_demo').update({role:'elder',townshipId:'other'});await assert.rejects(redeem('elder_demo',input),reason('WALLET_ACCESS_DENIED'));
      await db.doc('users/elder_demo').update({townshipId});assert.deepEqual(await redeem('elder_demo',input),result);
      await assert.rejects(redeem('elder_demo',{...input,voucherId:'another'}),reason('IDEMPOTENCY_KEY_REUSED'));
    });

    await t.test('synthetic approved policy credits both actual participants once and independently of phone-help outing exclusion',async()=>{
      const policy=await install(),done=await finishReady(),amount=await testAmount();
      for(const role of ['elder','helper']){
        const uid=`${role}_demo`,pid=done.participationIds[role],claim=await stored(`rewardClaims/${pid}`),entry=await stored(`wallets/${uid}/entries/${rewardEntryId(pid)}`);
        assert.equal(await balance(uid),amount);assert.equal(claim.status,'credited');assert.equal(claim.amountCoins,amount);
        assert.equal(claim.ruleVersion,policy.version);assert.equal(entry.ownerUid,uid);assert.equal(entry.participationId,pid);assert.equal(entry.completionEventId,done.completionEventId);
        assert.equal(entry.amount,amount);assert.equal(entry.rateCoins,amount);assert.equal(entry.balanceAfter,amount);
        assert.equal((await stored(`completionMarkers/${pid}`)).outingClassification,'does_not_count');
      }
      await call('elder_demo','transitionRequest',command({requestId:done.id,action:'confirm'}));
      assert.equal((await entries('elder_demo')).length,1);assert.equal((await entries('helper_demo')).length,1);
      const redemption=await redeem('helper_demo');assert.equal(redemption.data.balance,0);
    });

    await t.test('synthetic activity policy credits standalone elders and accompanied participants through one canonical activity identity',async()=>{
      await install('activity_attendance');const amount=await testAmount();
      const submitted=(await call('elder_solo','submitActivityAttendance',command({activityId:'activity_demo_attendance'}))).data.attendance;
      await call('coordinator_demo','reviewActivityAttendance',command({attendanceId:submitted.id,decision:'verify',verificationMethod:'organizer_roster',note:'Isolated test roster.'}));
      assert.equal(await balance('elder_solo'),amount);
      const a=await stored('activities/activity_garden');let now=Timestamp.now();const service=createSessionService(db,()=>now);
      const r=(await service.createRequest('elder_demo',command({elderId:'elder_demo',activityId:'activity_garden',placeId:a.placeId,startsAt:a.startsAt.toDate().toISOString(),endsAt:a.endsAt.toDate().toISOString(),taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'any'}))).data.request;
      await service.assignRequest('coordinator_demo',command({requestId:r.id,pairingId:'pairing_demo'}));
      const act=(uid,action)=>service.transitionRequest(uid,command({requestId:r.id,action}));
      await act('helper_demo','accept');now=a.startsAt;await act('helper_demo','start');now=a.endsAt;await act('helper_demo','finish');
      await act('elder_demo','confirm');const done=(await act('helper_demo','confirm')).data.request;
      for(const role of ['elder','helper']){
        assert.equal(await balance(`${role}_demo`),amount);assert.equal((await entries(`${role}_demo`)).length,1);
        await reconcileVerifiedParticipation(db,done.participationIds[role],()=>now);assert.equal(await balance(`${role}_demo`),amount);
      }
      assert.equal(done.completionEventId,completionId('activity_garden',r.id));
    });

    await t.test('pending/missing-claim recovery races use verified evidence, preserve first verification and never credit a policy version twice',async()=>{
      const done=await finishReady(),pid=done.participationIds.elder,first=(await stored(`participations/${pid}`)).verifiedAt;
      await install();const amount=await testAmount();
      await Promise.all([reconcileVerifiedParticipation(db,pid),reconcileVerifiedParticipation(db,pid)]);
      assert.equal(await balance('elder_demo'),amount);assert.equal((await entries('elder_demo')).length,1);
      assert.equal((await stored(`rewardClaims/${pid}`)).verifiedAt.toMillis(),first.toMillis());
      await db.doc(`rewardPolicyVersions/${policyId}`).update({version:'test-only-v2',rules:(await rulesFor()).map((r)=>({...r,rateCoins:amount*2}))});
      await reconcileVerifiedParticipation(db,pid);assert.equal(await balance('elder_demo'),amount);
      await db.doc(`rewardClaims/${pid}`).delete();await reconcileVerifiedParticipation(db,pid);
      assert.equal((await stored(`rewardClaims/${pid}`)).status,'credited');assert.equal(await balance('elder_demo'),amount);
      assert.equal((await stored(`rewardClaims/${pid}`)).ruleVersion,'test-only-v1');
      const entry=await stored(`wallets/elder_demo/entries/${rewardEntryId(pid)}`);await db.doc(`wallets/elder_demo/entries/${rewardEntryId(pid)}`).delete();
      try{await assert.rejects(reconcileVerifiedParticipation(db,pid),reason('REWARD_ACCOUNTING_CONFLICT'));assert.equal(await balance('elder_demo'),amount);}
      finally{await db.doc(`wallets/elder_demo/entries/${rewardEntryId(pid)}`).set(entry);}
    });

    await t.test('unknown and explicitly ineligible rules do not fabricate credits; later policy changes do not rewrite terminal ineligibility',async()=>{
      const rules=await rulesFor();await testPolicy([{...rules[0],eligible:false,rateCoins:null,reason:'SYNTHETIC_EXCLUSION'}]);
      const done=await finishReady();
      assert.equal((await stored(`rewardClaims/${done.participationIds.elder}`)).status,'ineligible');
      assert.equal((await stored(`rewardClaims/${done.participationIds.elder}`)).amountCoins,0);
      assert.equal((await stored(`rewardClaims/${done.participationIds.helper}`)).status,'pending_policy');
      await install();await reconcileVerifiedParticipation(db,done.participationIds.elder);assert.equal(await balance('elder_demo'),0);
      await reconcileVerifiedParticipation(db,done.participationIds.helper);assert.equal(await balance('helper_demo'),await testAmount());
    });

    await t.test('unverified or altered sources cannot be reconciled into a reward',async()=>{
      await install();const eventId=completionId(null,'request_demo_ready'),pid=participationId(eventId,'elder_demo');
      await assert.rejects(reconcileVerifiedParticipation(db,pid),reason('COMPLETION_NOT_VERIFIED'));
      // Complete without a policy, then alter the private source to model an
      // inconsistent import. Reconciliation must distrust the participation alone.
      await db.doc(`rewardPolicies/${townshipId}`).set({activeVersionId:null});const done=await finishReady();await install();
      await db.doc('requests/request_demo_ready').update({state:'awaiting_confirmation'});
      await assert.rejects(reconcileVerifiedParticipation(db,done.participationIds.elder),reason('COMPLETION_NOT_VERIFIED'));
      assert.equal(await balance('elder_demo'),0);assert.equal((await entries('elder_demo')).length,0);
    });

    await t.test('a failed second-participant credit rolls back final confirmation and every first-participant financial effect',async()=>{
      await install();for(const action of ['accept','start','finish'])await call('helper_demo','transitionRequest',command({requestId:'request_demo_ready',action}));
      await call('elder_demo','transitionRequest',command({requestId:'request_demo_ready',action:'confirm'}));
      await db.doc('wallets/helper_demo').update({balance:-1});const input=command({requestId:'request_demo_ready',action:'confirm'});
      await assert.rejects(call('helper_demo','transitionRequest',input),reason('INVALID_WALLET_BALANCE'));
      assert.equal(await balance('elder_demo'),0);assert.equal((await entries('elder_demo')).length,0);
      assert.equal((await db.collection('participations').get()).size,0);assert.equal((await db.collection('rewardClaims').get()).size,0);
      const request=await stored('requests/request_demo_ready');assert.equal(request.state,'awaiting_confirmation');assert.equal(request.helperConfirmation,null);
      await db.doc('wallets/helper_demo').update({balance:0});await call('helper_demo','transitionRequest',input);assert.equal(await balance('elder_demo'),await testAmount());
    });

    await t.test('concurrent completion credit and voucher debit preserve the wallet and both immutable ledger entries',async()=>{
      const done=await finishReady();await install();const amount=await testAmount();await db.doc('wallets/elder_demo').update({balance:amount});
      await Promise.all([reconcileVerifiedParticipation(db,done.participationIds.elder),redeem()]);
      assert.equal(await balance('elder_demo'),amount);assert.equal((await entries('elder_demo')).length,2);
    });

    await t.test('owner/township-scoped financial queries work while family, other participants and direct policy/financial writes fail',async()=>{
      await db.doc('wallets/elder_demo').update({balance:await testAmount()});const result=await redeem(),id=result.data.redemption.id;
      for(const uid of ['elder_demo','coordinator_demo'])await read(uid,`redemptions/${id}`);
      for(const uid of ['family_demo','family_unrelated','helper_demo','elder_solo'])await assert.rejects(read(uid,`redemptions/${id}`),{code:'permission-denied'});
      const fs=clients.get('elder_demo').firestore;
      for(const [path,order]of [['redemptions','issuedAt'],['wallets/elder_demo/entries','createdAt']]){
        assert.equal((await getDocsFromServer(query(collection(fs,path),where('ownerUid','==','elder_demo'),where('townshipId','==',townshipId),orderBy(order,'desc')))).size,1);
        await assert.rejects(getDocsFromServer(collection(fs,path)),{code:'permission-denied'});
      }
      await db.doc('users/coordinator_demo').update({townshipId:'other'});await assert.rejects(read('coordinator_demo',`redemptions/${id}`),{code:'permission-denied'});
      for(const uid of ['elder_demo','family_demo','coordinator_demo']){
        const userDb=clients.get(uid).firestore;
        for(const path of [`redemptions/${id}`,'wallets/elder_demo',`wallets/elder_demo/entries/${result.data.entryId}`,`rewardPolicies/${townshipId}`,`rewardPolicyVersions/${policyId}`]){
          await assert.rejects(setDoc(doc(userDb,path),{balance:100000,activeVersionId:'fake'}),{code:'permission-denied'});
        }
        await assert.rejects(read(uid,`rewardPolicies/${townshipId}`),{code:'permission-denied'});
      }
      await assert.rejects(updateDoc(doc(fs,`wallets/elder_demo/entries/${result.data.entryId}`),{amount:0}),{code:'permission-denied'});
      await assert.rejects(deleteDoc(doc(fs,`redemptions/${id}`)),{code:'permission-denied'});
    });

    await t.test('published successful redemption fixtures match isolated sufficient-balance service responses for both roles',async()=>{
      const fixtures=JSON.parse(await readFile(new URL('../docs/fixtures/stage5_wallet.json',import.meta.url),'utf8'));
      const now=Timestamp.fromDate(new Date(fixtures.serverTime));await resetDemo(admin);await seedDemo(admin,now.toDate());const service=createWalletService(db,()=>now);
      for(const name of ['elder','helper']){
        const example=fixtures.isolatedRedemptionUiScenarios[name];await db.doc(`wallets/${example.callerUid}`).update({balance:example.hypotheticalOpeningBalance});
        assert.deepEqual(await service.redeemDemoVoucher(example.callerUid,example.input),example.output);
        const entry=example.debitEntry;assert.deepEqual(wireRecord(entry.id,await stored(`wallets/${example.callerUid}/entries/${entry.id}`)),entry);
      }
    });

    await t.test('seed preserves accounted balances; reset removes demo financial history and preserves unrelated accounts/history',async()=>{
      await install();const done=await finishReady();await redeem();const helperBalance=await balance('helper_demo');
      await seedDemo(admin);assert.equal(await balance('helper_demo'),helperBalance);assert.equal((await entries('helper_demo')).length,1);
      const external='test_stage5_external',externalPid=participationId(done.completionEventId,external),amount=await testAmount();
      const paths=[`participations/${externalPid}`,`rewardClaims/${externalPid}`,`wallets/${external}`,`wallets/${external}/entries/external`, 'redemptions/test_stage5_external'];
      try{
        await db.doc(paths[0]).set({beneficiaryUid:external,completionEventId:done.completionEventId,sourceRequestIds:['request_demo_ready']});
        await db.doc(paths[1]).set({beneficiaryUid:external,status:'credited'});await db.doc(paths[2]).set({ownerUid:external,townshipId,balance:amount});
        await db.doc(paths[3]).set({ownerUid:external,participationId:externalPid,amount});await db.doc(paths[4]).set({ownerUid:external,townshipId});
        await resetDemo(admin);for(const path of paths)assert.ok(await stored(path));
        assert.ok(await stored(`completionEvents/${done.completionEventId}`));assert.equal((await entries('elder_demo')).length,0);assert.equal((await entries('helper_demo')).length,0);
        assert.equal((await db.collection('redemptions').where('ownerUid','==','elder_demo').get()).size,0);
        assert.equal((await db.collection('commandReceipts').where('functionName','==','redeemDemoVoucher').get()).size,0);
        await seedDemo(admin);assert.equal(await balance('elder_demo'),0);assert.equal((await stored(`rewardPolicies/${townshipId}`)).activeVersionId,null);
      }finally{for(const path of paths)await db.doc(path).delete();await db.doc(`completionEvents/${done.completionEventId}`).delete();}
    });
  }finally{
    for(const{app,firestore}of clients.values()){await terminate(firestore);await deleteApp(app);}
    await resetDemo(admin);await seedDemo(admin);await db.doc(`rewardPolicyVersions/${policyId}`).delete();await db.terminate();await deleteAdminApp(admin.app);
  }
});
