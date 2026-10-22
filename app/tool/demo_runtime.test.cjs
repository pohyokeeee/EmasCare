const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {once}=require('node:events');
const {createPreviewServer}=require('./serve.cjs');
const {validateHub,validateOwner,exportLocation,digest,normalized,selectJava}=require('./demo_runtime.cjs');
const root=path.resolve(__dirname,'../..'),entry=path.join(root,'node_modules/firebase-tools/lib/bin/firebase.js');
const services={auth:{host:'127.0.0.1',port:9099},firestore:{host:'127.0.0.1',port:8080},functions:{host:'127.0.0.1',port:5001}};
const actual={pid:1234,started:'2026-10-22T01:00:00Z',command:`node "${entry}" emulators:start --project demo-emascare`};
test('old JAVA_HOME falls back to a supported installed JDK, while a supported preference is retained',()=>{
  const versions={old:16,installed:25,preferred:21,missing:0};
  assert.equal(selectJava(['old','installed'],p=>versions[p]),'installed');
  assert.equal(selectJava(['preferred','installed'],p=>versions[p]),'preferred');
  assert.throws(()=>selectJava(['old','missing'],p=>versions[p]),/JDK 21/);
});
test('emulator reuse rejects foreign projects, checkouts, hosts and incomplete ports',()=>{
  assert.doesNotThrow(()=>validateHub(services,root,actual));
  for(const command of [actual.command.replace('demo-emascare','real-project'),actual.command.replace(entry,path.join(os.tmpdir(),'firebase.js'))])assert.throws(()=>validateHub(services,root,{...actual,command}));
  assert.throws(()=>validateHub({...services,auth:{host:'192.0.2.2',port:9099}},root,actual));
  assert.throws(()=>validateHub({...services,functions:{host:'127.0.0.1',port:5002}},root,actual));
  assert.throws(()=>validateHub({...services,firestore:null},root,actual));
});
test('stop ownership rejects PID reuse and foreign entry paths rather than trusting saved files',()=>{
  const owner={pid:actual.pid,started:actual.started,commandHash:digest(actual.command),entry};
  assert.equal(validateOwner(owner,actual,root),true);
  for(const changed of [{...actual,started:'2026-10-23T00:00:00Z'},{...actual,command:'another program'},{...actual,pid:5678},null])assert.equal(validateOwner(owner,changed,root),false);
  assert.equal(validateOwner({...owner,entry:path.join(os.tmpdir(),'other.js')},actual,root),false);
});
test('restart requires complete Auth/Firestore export and rejects path traversal before import',()=>{
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'emascare-launcher-'));
  try{
    const folder=path.join(fixture,'.cache/ui-demo/exports/current'),auth=path.join(folder,'auth_export'),firestore=path.join(folder,'firestore_export');
    fs.mkdirSync(auth,{recursive:true});fs.mkdirSync(firestore,{recursive:true});
    const write=data=>fs.writeFileSync(path.join(folder,'firebase-export-metadata.json'),JSON.stringify(data));
    fs.writeFileSync(path.join(auth,'accounts.json'),JSON.stringify({users:[{localId:'demo-only'}]}));
    fs.writeFileSync(path.join(firestore,'metadata'),'test-only');
    const manifest={auth:{path:'auth_export'},firestore:{metadata_file:'firestore_export/metadata'}};
    write(manifest);assert.equal(exportLocation(fixture,folder),folder);
    write({...manifest,firestore:{metadata_file:'../../outside'}});assert.throws(()=>exportLocation(fixture,folder));
    write(manifest);fs.unlinkSync(path.join(auth,'accounts.json'));assert.throws(()=>exportLocation(fixture,folder));
    assert.throws(()=>exportLocation(fixture,path.join(fixture,'foreign-export')));
  }finally{
    const resolved=path.resolve(fixture),temp=path.resolve(os.tmpdir())+path.sep;
    assert(resolved.startsWith(temp)&&path.basename(resolved).startsWith('emascare-launcher-'));
    fs.rmSync(resolved,{recursive:true,force:true});
  }
});
test('preview health identifies the checkout without exposing filesystem paths; assets remain uncached',async()=>{
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'emascare-launcher-'));
  fs.writeFileSync(path.join(fixture,'index.html'),'<title>Isolated preview test</title>');
  fs.writeFileSync(path.join(fixture,'firebase_local.mjs'),'// isolated test bootstrap');
  const server=createPreviewServer(fixture);server.listen(0,'127.0.0.1');await once(server,'listening');const port=server.address().port;
  try{
    const response=await fetch(`http://127.0.0.1:${port}/__emascare/health`),info=await response.json();
    assert.deepEqual(info,{project:'demo-emascare',workspace:digest(normalized(path.join(root,'app')))});
    assert.equal(response.headers.get('cache-control'),'no-store');
    assert(!(JSON.stringify(info).includes(root)));
    const asset=await fetch(`http://127.0.0.1:${port}/firebase_local.mjs`);assert.equal(asset.status,200);assert.equal(asset.headers.get('cache-control'),'no-store');
    const missing=await fetch(`http://127.0.0.1:${port}/not-a-file`);assert.equal(missing.status,404);
  }finally{
    await new Promise(r=>server.close(r));
    const resolved=path.resolve(fixture);assert(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('emascare-launcher-'));
    fs.rmSync(resolved,{recursive:true,force:true});
  }
});
