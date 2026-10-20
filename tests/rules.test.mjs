import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, getDocs, collection, query, where, orderBy, setDoc, updateDoc, deleteDoc} from 'firebase/firestore';
import {fixtureDocuments, townshipId} from '../scripts/fixtures.mjs';
import {localEnvironment, projectId} from '../scripts/local.mjs';

test('Firestore foundation policies against the real rules emulator', {timeout:120000}, async (t) => {
  localEnvironment();
  const env = await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,
    rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')}});
  const user = (uid,claims = {}) => env.authenticatedContext(uid,claims).firestore();
  const read = (db,path) => getDoc(doc(db,path));
  const admin = async (action) => env.withSecurityRulesDisabled((context) => action(context.firestore()));
  const owned = [];
  try {
    await admin(async (db) => {
      // The browser SDK requires JS Dates rather than Admin Timestamp objects.
      const wire = (value) => {
        if (value && typeof value.toDate === 'function') return value.toDate();
        if (Array.isArray(value)) return value.map(wire);
        if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,wire(v)]));
        return value;
      };
      for (const {path,data} of fixtureDocuments()) await setDoc(doc(db,path),wire(data));
      const testDocs = {
        'users/rules_other_coord':{displayName:'Other Coordinator',role:'coordinator',townshipId:'other_township',householdId:null,locale:'en'},
        'activities/rules_other_activity':{townshipId:'other_township',startsAt:new Date()},
        'wallets/rules_other_wallet':{ownerUid:'rules_other_elder',townshipId:'other_township',balance:0},
        'wallets/elder_demo/entries/rules_permission_sample':{ownerUid:'elder_demo',townshipId},
        'dailyStatuses/rules_history':{elderId:'elder_demo',householdId:'household_demo',localDate:'2026-10-20',state:'ok',submittedAt:new Date()},
        'dailyStatuses/rules_solo':{elderId:'elder_solo',householdId:'household_solo',localDate:'2026-10-20',state:'ok',submittedAt:new Date()},
        'commandReceipts/rules_private':{actorUid:'elder_demo'},
        'foundationProbes/rules_private':{actorUid:'elder_demo'},
      };
      for (const [path,data] of Object.entries(testDocs)) { await setDoc(doc(db,path),data); owned.push(path); }
    });
    await t.test('anonymous clients and identities without a server profile cannot read township records', async () => {
      await assertFails(read(env.unauthenticatedContext().firestore(),'activities/activity_garden'));
      await assertFails(read(user('missing_profile',{role:'coordinator',townshipId}),'activities/activity_garden'));
    });
    await t.test('own profiles and household membership are enforced without token role overrides', async () => {
      await assertSucceeds(read(user('elder_demo'),'users/elder_demo'));
      await assertSucceeds(read(user('family_demo'),'households/household_demo'));
      await assertFails(read(user('family_unrelated'),'households/household_demo'));
      await assertFails(read(user('helper_demo',{role:'coordinator'}),'users/elder_demo'));
      await assertSucceeds(read(user('coordinator_demo'),'users/elder_demo'));
      await assertFails(read(user('rules_other_coord'),'users/elder_demo'));
    });
    await t.test('private settings and individual helper availability stay private', async () => {
      await assertSucceeds(read(user('elder_demo'),'elderSettings/elder_demo'));
      await assertSucceeds(read(user('coordinator_demo'),'elderSettings/elder_demo'));
      await assertFails(read(user('family_demo'),'elderSettings/elder_demo'));
      await assertSucceeds(read(user('helper_demo'),'helperProfiles/helper_demo'));
      await assertSucceeds(read(user('coordinator_demo'),'helperProfiles/helper_demo'));
      await assertFails(read(user('elder_demo'),'helperProfiles/helper_demo'));
      await assertFails(read(user('rules_other_coord'),'helperProfiles/helper_demo'));
    });
    await t.test('catalog queries must be constrained to the current township', async () => {
      const elder = user('elder_demo');
      const snapshot = await assertSucceeds(getDocs(query(collection(elder,'activities'),where('townshipId','==',townshipId),orderBy('startsAt'))));
      assert.equal(snapshot.size,2);
      await assertFails(getDocs(collection(elder,'activities')));
      await assertFails(read(elder,'activities/rules_other_activity'));
      await assertSucceeds(read(elder,'places/place_garden'));
      await assertSucceeds(read(elder,'voucherCatalog/voucher_demo'));
    });
    await t.test('accepted pairings are limited to their participants and same-township coordinator', async () => {
      for (const uid of ['elder_demo','helper_demo','coordinator_demo']) await assertSucceeds(read(user(uid),'pairings/pairing_demo'));
      for (const uid of ['elder_solo','family_unrelated','family_demo','rules_other_coord']) await assertFails(read(user(uid),'pairings/pairing_demo'));
    });
    await t.test('sharing consent permits scoped daily history; unrelated and broad queries are denied', async () => {
      const family = user('family_demo');
      await assertSucceeds(read(family,'dailyStatuses/rules_history'));
      await assertFails(read(user('family_unrelated'),'dailyStatuses/rules_history'));
      await assertFails(read(family,'dailyStatuses/rules_solo'));
      await assertSucceeds(getDocs(query(collection(family,'dailyStatuses'),where('elderId','==','elder_demo'),
        where('householdId','==','household_demo'),orderBy('localDate','desc'))));
      await assertFails(getDocs(collection(family,'dailyStatuses')));
    });
    await t.test('withdrawal blocks old family history even if the household projection is stale', async () => {
      await admin((db) => updateDoc(doc(db,'elderSettings/elder_demo'),{familySharingEnabled:false}));
      try {
        await assertFails(read(user('family_demo'),'dailyStatuses/rules_history'));
        await assertSucceeds(read(user('elder_demo'),'dailyStatuses/rules_history'));
        await assertSucceeds(read(user('coordinator_demo'),'dailyStatuses/rules_history'));
      } finally { await admin((db) => updateDoc(doc(db,'elderSettings/elder_demo'),{familySharingEnabled:true})); }
    });
    await t.test('both wallet roles have own access; family and other participants never inherit financial access', async () => {
      await assertSucceeds(read(user('elder_demo'),'wallets/elder_demo'));
      await assertSucceeds(read(user('helper_demo'),'wallets/helper_demo'));
      await assertSucceeds(read(user('elder_demo'),'wallets/elder_demo/entries/rules_permission_sample'));
      await assertSucceeds(read(user('coordinator_demo'),'wallets/elder_demo'));
      await assertFails(read(user('family_demo'),'wallets/elder_demo'));
      await assertFails(read(user('family_demo'),'wallets/elder_demo/entries/rules_permission_sample'));
      await assertFails(read(user('helper_demo'),'wallets/elder_demo'));
      await assertFails(read(user('coordinator_demo'),'wallets/rules_other_wallet'));
    });
    await t.test('all direct domain writes, self-promotion, deletes and receipt reads are denied', async () => {
      for (const path of ['users/elder_demo','households/household_demo','elderSettings/elder_demo','wallets/elder_demo',
        'wallets/elder_demo/entries/fake','helperProfiles/helper_demo','activities/fake','pairings/fake',
        'requests/fake','activityAttendances/fake','rewardClaims/fake','commandReceipts/fake']) {
        await assertFails(setDoc(doc(user('elder_demo'),path),{role:'coordinator',balance:100000}));
      }
      await assertFails(updateDoc(doc(user('coordinator_demo'),'users/elder_demo'),{role:'coordinator'}));
      await assertFails(deleteDoc(doc(user('elder_demo'),'wallets/elder_demo')));
      await assertFails(read(user('elder_demo'),'commandReceipts/rules_private'));
      await assertFails(read(user('coordinator_demo'),'foundationProbes/rules_private'));
    });
  } finally {
    await admin(async (db) => { for (const path of owned) await deleteDoc(doc(db,path)); });
    await env.cleanup();
  }
});
