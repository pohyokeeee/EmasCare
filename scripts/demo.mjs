import {pathToFileURL} from 'node:url';
import {localEnvironment, projectId} from './local.mjs';
import {demoAccounts, demoPassword, fixtureDocuments} from './fixtures.mjs';
const resettableCommands = new Set(['foundationProbe','saveElderSettings','submitCheckIn','recordPhoneResponse',
  'setHelperAvailability','createRequest','assignRequest','transitionRequest']);

export async function demoClients() {
  const env = localEnvironment();
  for (const name of ['GCLOUD_PROJECT','FIREBASE_AUTH_EMULATOR_HOST','FIRESTORE_EMULATOR_HOST','METADATA_SERVER_DETECTION']) process.env[name] = env[name];
  // Dynamic import ensures the guard runs before Admin initialization.
  const {initializeApp} = await import('firebase-admin/app');
  const {getAuth} = await import('firebase-admin/auth');
  const {getFirestore} = await import('firebase-admin/firestore');
  const app = initializeApp({projectId}, `demo-script-${crypto.randomUUID()}`);
  return {app, auth:getAuth(app), db:getFirestore(app)};
}

export async function seedDemo({auth, db}, now = new Date()) {
  assertClientsLocal(auth, db);
  for (const {uid,email,displayName} of demoAccounts) {
    const values = {email,displayName,password:demoPassword,emailVerified:true,disabled:false};
    try { await auth.updateUser(uid, values); }
    catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      await auth.createUser({uid,...values});
    }
  }
  const batch = db.batch();
  const fixtures = fixtureDocuments(now);
  for (const {path,data} of fixtures) if (!path.startsWith('helperReservations/')) batch.set(db.doc(path), data);
  await batch.commit();
  // A reservation document can also contain unrelated bookings. Preserve them.
  for (const {path,data} of fixtures.filter((item) => item.path.startsWith('helperReservations/'))) {
    await db.runTransaction(async (tx) => {
      const ref = db.doc(path), before = (await tx.get(ref)).data();
      tx.set(ref,{...data,slots:[...(before?.slots ?? []).filter((slot) => slot.requestId !== 'request_demo_ready'),...data.slots]});
    });
  }
}

export async function resetDemo({auth, db}) {
  assertClientsLocal(auth, db);
  await resetCompanions(db);
  // Explicit fixtures plus check-in history owned by the known demo elders;
  // no database flush or recursive delete. Other actors' data is untouched.
  const batch = db.batch();
  for (const {path} of fixtureDocuments()) if (!path.startsWith('helperReservations/')) batch.delete(db.doc(path));
  for (const {uid} of demoAccounts) batch.delete(db.doc(`foundationProbes/${uid}`));
  await batch.commit();
  for (const {uid,role} of demoAccounts) {
    if (role !== 'elder') continue;
    for (const collection of ['checkins','dailyStatuses']) {
      const snapshots = await db.collection(collection).where('elderId','==',uid).get();
      await deleteOwnedDocuments(db, snapshots.docs);
    }
  }
  for (const {uid} of demoAccounts) {
    const receipts = await db.collection('commandReceipts').where('actorUid','==',uid).get();
    await deleteOwnedDocuments(db, receipts.docs.filter((receipt) => resettableCommands.has(receipt.data().functionName)));
  }
  for (const {uid} of demoAccounts) {
    try { await auth.deleteUser(uid); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  }
}

async function resetCompanions(db) {
  const actors = new Set(demoAccounts.map((account) => account.uid));
  const requests = new Map(), participants = new Map(), events = new Set(), helpers = new Set();
  for (const {uid,role} of demoAccounts) {
    if (role === 'elder') {
      for (const snapshot of (await db.collection('requests').where('elderId','==',uid).get()).docs) requests.set(snapshot.id,snapshot);
      for (const collection of ['activityElderLocks','activityAttendances']) {
        await deleteOwnedDocuments(db,(await db.collection(collection).where('elderId','==',uid).get()).docs);
      }
    }
    for (const snapshot of (await db.collection('participations').where('beneficiaryUid','==',uid).get()).docs) participants.set(snapshot.id,snapshot);
  }
  for (const [id,snapshot] of requests) {
    if (snapshot.data().helperId) helpers.add(snapshot.data().helperId);
    for (const row of (await db.collection('participations').where('sourceRequestIds','array-contains',id).get()).docs) participants.set(row.id,row);
  }
  for (const [id,snapshot] of participants) {
    const data = snapshot.data(), remaining = (data.sourceRequestIds ?? []).filter((requestId) => !requests.has(requestId));
    if (!actors.has(data.beneficiaryUid) && remaining.length) {
      await snapshot.ref.update({sourceRequestIds:remaining});
      continue;
    }
    events.add(data.completionEventId);
    const cleanup = db.batch();
    cleanup.delete(snapshot.ref);
    cleanup.delete(db.doc(`rewardClaims/${id}`));
    cleanup.delete(db.doc(`completionMarkers/${id}`));
    await cleanup.commit();
  }
  for (const helperId of helpers) {
    for (const row of (await db.collection('helperReservations').where('helperId','==',helperId).get()).docs) {
      const slots = row.data().slots.filter((slot) => !requests.has(slot.requestId));
      if (slots.length) await row.ref.update({slots});
      else await row.ref.delete();
    }
    const ref = db.doc(`helperSessions/${helperId}`), active = (await ref.get()).data();
    if (active && (!active.requestId || requests.has(active.requestId))) await ref.delete();
  }
  await deleteOwnedDocuments(db,[...requests.values()]);
  // Activity events can be shared with other elders: remove only empty ones.
  for (const id of events) {
    if ((await db.collection('participations').where('completionEventId','==',id).limit(1).get()).empty) await db.doc(`completionEvents/${id}`).delete();
  }
}

async function deleteOwnedDocuments(db, documents) {
  for (let offset = 0; offset < documents.length; offset += 400) {
    const cleanup = db.batch();
    for (const snapshot of documents.slice(offset,offset+400)) cleanup.delete(snapshot.ref);
    await cleanup.commit();
  }
}

function assertClientsLocal(auth, db) {
  localEnvironment();
  if (auth.app.options.projectId !== projectId || db.projectId !== projectId) {
    throw new Error('Refusing non-demo Admin clients');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const action = process.argv[2];
  if (!['seed','reset'].includes(action)) throw new Error('Use: node scripts/demo.mjs seed|reset');
  const clients = await demoClients();
  try {
    if (action === 'reset') await resetDemo(clients);
    await seedDemo(clients);
    console.log(`${action === 'reset' ? 'Reset and reseeded' : 'Seeded'} ${demoAccounts.length} emulator accounts in ${projectId}.`);
    console.log('Emulator-only password: ' + demoPassword);
    for (const account of demoAccounts) console.log(`${account.role}: ${account.email} (${account.uid})`);
  } finally {
    await clients.db.terminate();
    const {deleteApp} = await import('firebase-admin/app');
    await deleteApp(clients.app);
  }
}
