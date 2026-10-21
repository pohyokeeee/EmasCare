// Read-only emulator verification. Does not seed/reset or change domain data.
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore, connectFirestoreEmulator, getDocsFromServer, getDocFromServer,
  collection, query, where, orderBy, doc, terminate} from 'firebase/firestore';
import {localEnvironment, projectId} from '../../scripts/local.mjs';
import {demoAccounts, demoPassword} from '../../scripts/fixtures.mjs';

localEnvironment(); // Refuse conflicting projects or non-loopback emulator hosts.
let checks = 0;
for (const account of demoAccounts) {
  const app = initializeApp({apiKey:'local-demo-key', projectId, appId:'1:1234567890:web:emascare-demo'}, `community-read-${account.uid}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings:true});
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  try {
    await signInWithEmailAndPassword(auth, account.email, demoPassword);
    const profile = (await getDocFromServer(doc(db, 'users', account.uid))).data();
    assert.equal(profile.role, account.role); checks++;
    await getDocsFromServer(query(collection(db, 'activities'), where('townshipId','==',profile.townshipId), orderBy('startsAt'))); checks++;
    await getDocsFromServer(query(collection(db, 'places'), where('townshipId','==',profile.townshipId))); checks++;
    if (['elder','helper'].includes(profile.role)) {
      const field = profile.role === 'elder' ? 'elderId' : 'helperId';
      // Resource-level sameTownship checks require BOTH constraints.
      const pairs = await getDocsFromServer(query(collection(db,'pairings'), where(field,'==',account.uid), where('townshipId','==',profile.townshipId)));
      assert(pairs.docs.every((d) => d.data()[field] === account.uid && d.data().townshipId === profile.townshipId)); checks++;
      if (profile.role === 'helper') { await getDocFromServer(doc(db,'helperProfiles',account.uid)); checks++; }
    } else if (profile.role === 'coordinator') {
      await getDocsFromServer(query(collection(db,'pairings'), where('townshipId','==',profile.townshipId), where('active','==',true))); checks++;
    } else {
      await assert.rejects(getDocFromServer(doc(db,'pairings','pairing_demo')), (error) => error.code === 'permission-denied'); checks++;
      await assert.rejects(getDocFromServer(doc(db,'helperProfiles','helper_demo')), (error) => error.code === 'permission-denied'); checks++;
    }
    await assert.rejects(getDocsFromServer(collection(db,'activities')), (error) => error.code === 'permission-denied'); checks++;
    console.log(`PASS ${account.email}: scoped catalog and permitted companion reads`);
  } finally {
    await terminate(db); await deleteApp(app);
  }
}
console.log(`Passed ${checks} real emulator read/permission checks; no domain data changed.`);
