import {createRequire} from 'node:module';
import {deleteApp} from 'firebase-admin/app';
import {demoClients} from './demo.mjs';
import {demoAccounts} from './fixtures.mjs';

const require=createRequire(import.meta.url);
if (process.argv.length>2) throw new Error('This local command takes no rate, owner or policy arguments.');
const {reconcileVerifiedParticipation}=require('../functions/lib/reconciliation.js');
const clients=await demoClients(); // exact local/demo guard runs before Admin init
try {
  let processed=0;
  for (const {uid,role} of demoAccounts) if (role==='elder'||role==='helper') {
    const participants=await clients.db.collection('participations').where('beneficiaryUid','==',uid).get();
    for (const snapshot of participants.docs) {
      const claim=await reconcileVerifiedParticipation(clients.db,snapshot.id);
      console.log(`${snapshot.id}: ${claim.status}`); processed++;
    }
  }
  console.log(`Reconciled ${processed} verified demo participations; no rate or policy was supplied by this script.`);
} finally { await clients.db.terminate(); await deleteApp(clients.app); }
