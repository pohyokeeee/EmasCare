import assert from 'node:assert/strict';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFunctions,connectFunctionsEmulator,httpsCallable} from 'firebase/functions';
import {getFirestore,connectFirestoreEmulator,doc,getDocFromServer,collection,query,where,orderBy,getDocsFromServer,terminate} from 'firebase/firestore';
import {localEnvironment,projectId,region} from './local.mjs';
import {demoAccounts,demoPassword} from './fixtures.mjs';
export const rehearsalIds=['request_demo_ready',...Array.from({length:4},(_,i)=>`request_rehearsal_${i+1}`)];

export async function requireIntegrationEmulators(transport=fetch) {
  localEnvironment();
  let response;
  try { response=await transport('http://127.0.0.1:4400/emulators',{signal:AbortSignal.timeout(5000)}); }
  catch { throw new Error('Start the local emulators in terminal 1 with npm.cmd run emulators, then retry in terminal 2.'); }
  assert(response.ok,'Local emulator hub did not respond successfully');
  const running=await response.json();
  for(const [name,port] of [['auth',9099],['firestore',8080],['functions',5001]]) {
    assert.equal(running[name]?.port,port,`Expected local ${name} emulator on ${port}`);
    assert(['127.0.0.1','localhost','::1'].includes(running[name]?.host),`Refusing non-loopback ${name} emulator`);
  }
}

// These are the same browser SDK boundaries used by Flutter, with real local
// Auth tokens. Neither token nor password is included in saved result files.
export async function integrationClients() {
  localEnvironment();
  const clients=new Map();
  const close=async()=>{
    for(const {app,db}of clients.values()){await terminate(db);await deleteApp(app);}
  };
  try {
    for(const account of demoAccounts){
      const app=initializeApp({projectId,apiKey:'local-demo-key',appId:'1:1234567890:web:integration'},`integration-${account.uid}-${crypto.randomUUID()}`);
      const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
      const db=getFirestore(app);connectFirestoreEmulator(db,'127.0.0.1',8080);
      const functions=getFunctions(app,region);connectFunctionsEmulator(functions,'127.0.0.1',5001);
      clients.set(account.uid,{app,db,functions});
      await signInWithEmailAndPassword(auth,account.email,demoPassword);
    }
  } catch(error) {await close();throw error;}
  return {
    async call(uid,name,input={contractVersion:1}) {
      const result=(await httpsCallable(clients.get(uid).functions,name,{timeout:120000})(input)).data;
      assert.equal(result?.contractVersion,1,`${name}: incompatible contract envelope`);
      assert(result.data&&typeof result.data==='object',`${name}: missing data envelope`);
      return result.data;
    },
    async read(uid,path){return (await getDocFromServer(doc(clients.get(uid).db,path))).data();},
    async list(uid,path,filters=[],sort=null){
      const clauses=filters.map(([field,value])=>where(field,'==',value));
      if(sort)clauses.push(orderBy(sort,'desc'));
      const rows=await getDocsFromServer(query(collection(clients.get(uid).db,path),...clauses));
      return rows.docs.map(d=>({id:d.id,...d.data()}));
    },close,
  };
}

export function command(key,fields={}) {return {contractVersion:1,idempotencyKey:key,...fields};}
