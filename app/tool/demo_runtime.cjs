const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const crypto = require('node:crypto');
const {spawn, spawnSync, execFileSync} = require('node:child_process');

const project = 'demo-emascare';
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const normalized = value => path.resolve(value).replaceAll('\\', '/').toLowerCase();
function contained(root, target) {
  const r = normalized(root), t = normalized(target);
  return t === r || t.startsWith(r + '/');
}
function validateHub(hub, root, processInfo) {
  for (const [name, port] of [['auth',9099],['firestore',8080],['functions',5001]]) {
    if (hub[name]?.port !== port || !['127.0.0.1','localhost','::1'].includes(hub[name]?.host))
      throw new Error(`Expected loopback ${name} on port ${port}; existing services were not changed.`);
  }
  const command = processInfo?.command?.replaceAll('\\','/').toLowerCase() ?? '';
  const cli = normalized(path.join(root,'node_modules/firebase-tools/lib/bin/firebase.js'));
  if (!command.includes(cli) || !/--project(?:=|\s+)demo-emascare(?:\s|$)/.test(command))
    throw new Error('The emulator hub belongs to another checkout/project. Existing services were not changed.');
}
function validateOwner(owner, actual, root) {
  return !!owner && !!actual && owner.pid === actual.pid && owner.started === actual.started &&
    owner.commandHash === digest(actual.command) && contained(root, owner.entry) &&
    actual.command.replaceAll('\\','/').toLowerCase().includes(normalized(owner.entry));
}
function exportLocation(root, folder) {
  if (!contained(path.join(root,'.cache/ui-demo/exports'), folder)) throw new Error('Export path must stay in the demo cache.');
  const manifest = JSON.parse(fs.readFileSync(path.join(folder,'firebase-export-metadata.json'),'utf8'));
  for (const [name, relative] of [['auth',manifest.auth?.path],['firestore',manifest.firestore?.metadata_file]]) {
    if (!relative || !contained(folder,path.resolve(folder,relative)) || !fs.existsSync(path.resolve(folder,relative)))
      throw new Error(`Incomplete or unsafe ${name} export; refusing to start with an empty store.`);
  }
  const accounts=JSON.parse(fs.readFileSync(path.join(folder,manifest.auth.path,'accounts.json'),'utf8'));
  if(!Array.isArray(accounts.users)) throw new Error('Auth export is incomplete; refusing an empty restart.');
  return folder;
}
function winProcesses() {
  if (process.platform !== 'win32') throw new Error('This launcher requires Windows PowerShell.');
  const command = 'Get-CimInstance Win32_Process | Select-Object @{n="pid";e={$_.ProcessId}},@{n="parent";e={$_.ParentProcessId}},@{n="name";e={$_.Name}},@{n="command";e={$_.CommandLine}},@{n="started";e={$_.CreationDate.ToUniversalTime().ToString("o")}} | ConvertTo-Json -Compress';
  return JSON.parse(execFileSync('powershell.exe',['-NoProfile','-Command',command],{encoding:'utf8',windowsHide:true,timeout:20000}));
}
async function json(url, init={}) {
  const response = await fetch(url,{...init,signal:AbortSignal.timeout(5000)});
  if (!response.ok) throw new Error(`Local service returned HTTP ${response.status}.`);
  return response.json();
}
function occupied(port) {
  return new Promise(resolve => {
    const socket = net.connect({host:'127.0.0.1',port});
    const finish = value => {socket.destroy();resolve(value);};
    socket.once('connect',()=>finish(true));socket.once('error',()=>finish(false));socket.setTimeout(1000,()=>finish(true));
  });
}
async function until(check, timeout, message) {
  const end = Date.now()+timeout;
  while (Date.now()<end) {if (await check()) return;await new Promise(r=>setTimeout(r,1000));}
  throw new Error(message);
}
function run(executable,args,root,env=process.env) {
  return new Promise((resolve,reject)=>{
    const child=spawn(executable,args,{cwd:root,env,windowsHide:true,stdio:'inherit'});
    child.once('error',reject);child.once('exit',code=>code===0?resolve():reject(new Error(`Local command failed (${code}): ${path.basename(args[0]??executable)}`)));
  });
}
function selectJava(candidates,majorVersion) {
  const home=[...new Set(candidates.filter(Boolean))].find(candidate=>majorVersion(candidate)>=21);
  if(!home)throw new Error('The Firestore emulator needs JDK 21+. Install one or set JAVA_HOME to a supported JDK.');
  return home;
}
function javaEnvironment(root) {
  const jdks=path.join(os.homedir(),'.jdks');
  const installed=fs.existsSync(jdks)?fs.readdirSync(jdks).sort().reverse().map(n=>path.join(jdks,n)):[];
  const systemJava=spawnSync('java',['-XshowSettings:properties','-version'],{encoding:'utf8',windowsHide:true,timeout:10000});
  const systemHome=systemJava.stderr?.match(/java\.home\s*=\s*(.+)/)?.[1]?.trim();
  const home=selectJava([process.env.JAVA_HOME,...installed,systemHome],candidate=>{
    if(!fs.existsSync(path.join(candidate,'bin/java.exe')))return 0;
    const version=spawnSync(path.join(candidate,'bin/java.exe'),['-version'],{encoding:'utf8',windowsHide:true,timeout:10000});
    return version.status===0?Number(version.stderr?.match(/(?:version\s+"|openjdk\s+)(\d+)/)?.[1]??0):0;
  });
  const env={...process.env,JAVA_HOME:home,FUNCTIONS_DISCOVERY_TIMEOUT:'120',GCLOUD_PROJECT:project,
    METADATA_SERVER_DETECTION:'none',FIREBASE_CLI_DISABLE_UPDATE_CHECK:'true',FIREBASE_EMULATORS_PATH:path.join(root,'.cache/firebase/emulators')};
  const key=Object.keys(env).find(k=>k.toLowerCase()==='path')??'PATH';env[key]=path.join(home,'bin')+path.delimiter+(env[key]??'');
  return env;
}

async function runtime({root=path.resolve(__dirname,'../..'),mode='start',skipBuild=false,previewPort=8090}={}) {
  if (!['start','status','backup','stop'].includes(mode)) throw new Error('Use start, status, backup or stop.');
  if (!Number.isInteger(previewPort)||previewPort<1024||previewPort>65535||[4000,4400,4500,5001,8080,9099,9150].includes(previewPort)) throw new Error('Choose a separate preview port (default 8090).');
  const cache=path.join(root,'.cache/ui-demo'),statePath=path.join(cache,'runtime.json'),latestPath=path.join(cache,'latest-export.json');
  fs.mkdirSync(cache,{recursive:true});
  let state=fs.existsSync(statePath)?JSON.parse(fs.readFileSync(statePath,'utf8')):{};
  const save=()=>fs.writeFileSync(statePath,JSON.stringify(state,null,2)+'\n');
  async function hub() {
    let services,locator;
    try {[services,locator]=await Promise.all([json('http://127.0.0.1:4400/emulators'),json('http://127.0.0.1:4400/')]);}
    catch {return null;}
    const actual=winProcesses().find(p=>p.pid===locator.pid);validateHub(services,root,actual);
    return {services,pid:locator.pid};
  }
  async function preview() {
    let info;
    try {info=await json(`http://127.0.0.1:${previewPort}/__emascare/health`);}catch{info=null;}
    if(info) {
      if(info.project!==project||info.workspace!==digest(normalized(path.join(root,'app')))) throw new Error('Different preview checkout.');
      return true;
    }else{
      // Older previews have no health endpoint. Reuse an identical local
      // Firebase bootstrap, but never claim ownership or stop that process.
      try {
        const response=await fetch(`http://127.0.0.1:${previewPort}/firebase_local.mjs`,{signal:AbortSignal.timeout(2000)});
        return response.ok&&digest(await response.text())===digest(fs.readFileSync(path.join(root,'app/web/firebase_local.mjs'),'utf8'));
      }catch{return false;}
    }
  }
  async function backup() {
    if(!await hub()) throw new Error('The local demo backend is not running; no export was attempted.');
    const folder=path.join(cache,'exports',new Date().toISOString().replaceAll(/[:.]/g,'-'));
    fs.mkdirSync(path.dirname(folder),{recursive:true});
    const response=await fetch('http://127.0.0.1:4400/_admin/export',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({path:folder,initiatedBy:'emascare-ui-demo',targets:['auth','firestore']}),signal:AbortSignal.timeout(55000)});
    if(!response.ok) throw new Error('Export failed; the backend will stay running.');
    exportLocation(root,folder);fs.writeFileSync(latestPath,JSON.stringify({folder})+'\n');
    return folder;
  }
  if(mode==='status') {
    const backend=await hub(),ready=await preview();
    const result={backend:backend?'running':'stopped',preview:ready?'running':'stopped',url:`http://127.0.0.1:${previewPort}`,savedExport:fs.existsSync(latestPath)};
    console.log(JSON.stringify(result,null,2));return result;
  }
  const lock=path.join(cache,'launcher.lock');
  const launcher=winProcesses().find(p=>p.pid===process.pid);
  if(!launcher)throw new Error('Cannot verify launcher process identity.');
  let fd;
  try{fd=fs.openSync(lock,'wx');}catch{
    let owner;
    try{owner=JSON.parse(fs.readFileSync(lock,'utf8'));}catch{throw new Error('Launcher lock has no valid owner. Inspect it and the original terminal before retrying.');}
    const actual=winProcesses().find(p=>p.pid===owner.pid);
    if(validateOwner(owner,actual,root))throw new Error('Another verified launcher process is running. Use its terminal; do not overlap actions.');
    fs.unlinkSync(lock);fd=fs.openSync(lock,'wx');
  }
  fs.writeFileSync(fd,JSON.stringify({pid:launcher.pid,started:launcher.started,commandHash:digest(launcher.command),entry:__filename}));
  try {
    if(mode==='backup') {const folder=await backup();console.log(`Saved local demo data: ${folder}`);return {folder};}
    if(mode==='stop') {
      let processes=winProcesses();
      const owned=Object.entries(state).filter(([,owner])=>validateOwner(owner,processes.find(p=>p.pid===owner.pid),root));
      if(owned.some(([name])=>name==='backend')) await backup();
      processes=winProcesses();
      // Refuse foreign/reused PIDs and never trust a PID without its start time.
      for(const [name,owner]of owned){
        if(!validateOwner(owner,processes.find(p=>p.pid===owner.pid),root))throw new Error('Service identity changed during backup; nothing further was stopped.');
        const descendants=[];let parents=new Set([owner.pid]);
        while(parents.size){const children=processes.filter(p=>parents.has(p.parent)&&!descendants.includes(p.pid));parents=new Set(children.map(p=>p.pid));descendants.push(...parents);}
        for(const child of descendants.reverse()){
          const before=processes.find(p=>p.pid===child),now=winProcesses().find(p=>p.pid===child);
          // Windows closes the console host with its owner. Terminating it
          // first can close the parent before the verified service shutdown.
          if(before.name==='conhost.exe')continue;
          if(now&&(now.started!==before.started||now.command!==before.command))throw new Error('Child PID was reused; refusing to stop it.');
          if(now)try{process.kill(child);}catch(e){if(e.code!=='ESRCH')throw e;}
        }
        if(!validateOwner(owner,winProcesses().find(p=>p.pid===owner.pid),root))throw new Error('Service identity changed; refusing to stop it.');
        process.kill(owner.pid);delete state[name];
      }
      save();console.log(`Stopped ${owned.length} launcher-owned service(s). Reused services were left running.`);return {stopped:owned.length};
    }
    const node=path.join(root,'node_modules/node/bin/node.exe'),cli=path.join(root,'node_modules/firebase-tools/lib/bin/firebase.js');
    if(!fs.existsSync(node)||!fs.existsSync(cli)) throw new Error('Run npm.cmd ci in the repository root first.');
    if(skipBuild&&!fs.existsSync(path.join(root,'app/build/web/index.html')))throw new Error('No web build exists. Run without -SkipBuild first.');
    const detach=(name,entry,args,env)=>{
      const out=fs.openSync(path.join(cache,`${name}.log`),'w'),err=fs.openSync(path.join(cache,`${name}.err.log`),'w');
      const child=spawn(node,[entry,...args],{cwd:root,env,detached:true,windowsHide:true,stdio:['ignore',out,err]});
      fs.closeSync(out);fs.closeSync(err);child.unref();
      return child;
    };
    const remember=async(name,child,entry)=>{
      await until(()=>{const actual=winProcesses().find(p=>p.pid===child.pid);if(!actual)return false;state[name]={pid:actual.pid,started:actual.started,commandHash:digest(actual.command),entry};save();return true;},15000,'Service did not start; inspect .cache/ui-demo logs.');
    };
    const existing=await hub();
    if(!existing){
      if((await Promise.all([4400,5001,8080,9099].map(occupied))).some(Boolean)) throw new Error('Some emulator ports are occupied but the demo is not ready. Preserve the existing services and inspect their logs.');
      const env=javaEnvironment(root);
      await run(node,[path.join(root,'node_modules/typescript/bin/tsc'),'-p','functions/tsconfig.json'],root,env);
      const args=['emulators:start','--project',project,'--only','auth,firestore,functions','--inspect-functions=9229'];
      if(fs.existsSync(latestPath)) args.push('--import',exportLocation(root,JSON.parse(fs.readFileSync(latestPath,'utf8')).folder));
      const child=detach('backend',cli,args,env);await remember('backend',child,cli);
      console.log('Starting the local backend; saved data will be imported when available…');
      await until(async()=>{
        try{process.kill(child.pid,0);}catch{throw new Error('Backend process exited during startup. Inspect .cache/ui-demo/backend logs; saved data was not reset.');}
        try{return !!await hub()&&fs.readFileSync(path.join(cache,'backend.log'),'utf8').includes('Loaded functions definitions');}catch{return false;}
      },180000,'Backend startup did not finish. Inspect .cache/ui-demo/backend logs; no reset was performed.');
      await run(node,[path.join(root,'scripts/prepare-integration.mjs')],root,env);
    }else console.log('Reusing this checkout’s running backend; existing demo records are preserved.');
    await run(node,[path.join(root,'scripts/check-integration.mjs')],root);
    if(!skipBuild) await run('powershell.exe',['-NoProfile','-File',path.join(root,'app/preview.ps1'),'-Mode','build'],root);
    if(!await preview()) {
      if(await occupied(previewPort)) throw new Error(`Port ${previewPort} belongs to another server. Choose -Port with an unused port.`);
      const entry=path.join(root,'app/tool/serve.cjs'),child=detach('preview',entry,[String(previewPort)],process.env);
      await remember('preview',child,entry);
      await until(preview,10000,'Preview did not start; inspect .cache/ui-demo/preview logs.');
    }
    console.log(`Ready: http://127.0.0.1:${previewPort}\nDemo accounts and walkthrough: app/FINAL_DEMO_GUIDE.md\nNo records were reset. Keep using this command for the next demo.`);
    return {ready:true,url:`http://127.0.0.1:${previewPort}`};
  }finally{fs.closeSync(fd);fs.unlinkSync(lock);}
}
module.exports={runtime,validateHub,validateOwner,exportLocation,contained,digest,normalized,selectJava};
if(require.main===module){
  const args=process.argv.slice(2),mode=args.shift()??'start';
  let port=8090;const at=args.indexOf('--port');if(at>=0){port=Number(args[at+1]);args.splice(at,2);}
  if(args.some(a=>a!=='--skip-build'))throw new Error('Unknown demo launcher option.');
  runtime({mode,previewPort:port,skipBuild:args.includes('--skip-build')}).catch(e=>{console.error(e.message);process.exitCode=1;});
}
