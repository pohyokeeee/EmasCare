const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web/voice_bridge.js'),'utf8');
function setup({denied=false,unsupported=false,oversized=false,late=false,autoStop=true,voices=[]}={}){
  let stops=0,requested=0,recorded=0,spoken=0,resolvePermission;
  const durations=[];
  const stream={getTracks:()=>[{stop:()=>stops++}]};
  class Recorder{
    static isTypeSupported(){return !unsupported;}
    constructor(_,options){this.mimeType=options.mimeType;this.state='inactive';}
    start(interval){assert.equal(interval,250);this.state='recording';recorded++;}
    stop(){this.state='inactive';this.ondataavailable({data:new Blob([oversized?new Uint8Array(1024*1024+1):'sample'])});this.onstop();}
  }
  const context={window:{addEventListener:()=>{},speechSynthesis:{getVoices:()=>voices,cancel:()=>{},speak:()=>spoken++}},navigator:{mediaDevices:{getUserMedia:()=>{requested++;if(denied){const e=new Error('Denied');e.name='NotAllowedError';return Promise.reject(e);}return late?new Promise(r=>resolvePermission=r):Promise.resolve(stream);}}},MediaRecorder:Recorder,Blob,Uint8Array,btoa:s=>Buffer.from(s,'binary').toString('base64'),SpeechSynthesisUtterance:class{constructor(text){this.text=text;}},setTimeout:(fn,ms)=>{durations.push(ms);return setTimeout(fn,ms===30000&&autoStop?0:ms);},clearTimeout};
  vm.runInNewContext(source,context);
  return{action:async command=>JSON.parse(await context.window.emasVoice.action(JSON.stringify(command))),counts:()=>({stops,requested,recorded,spoken}),durations,grant:()=>resolvePermission(stream)};
}
test('loading the voice bridge never asks for microphone permission',()=>{assert.equal(setup().counts().requested,0);});
test('explicit capture caps duration, normalizes real MIME and releases tracks',async()=>{const b=setup();const r=await b.action({action:'record'});assert.equal(r.error,false);assert.equal(r.mimeType,'audio/webm');assert.equal(Buffer.from(r.base64,'base64').toString(),'sample');assert(b.durations.includes(30000));assert(b.counts().stops>0);});
test('denied and unsupported recording retain manual fallback without fake audio',async()=>{for(const options of [{denied:true},{unsupported:true}]){const r=await setup(options).action({action:'record'});assert.equal(r.error,true);assert.equal(r.base64,undefined);}});
test('oversized audio is rejected before returning uploadable bytes',async()=>{const b=setup({oversized:true});const r=await b.action({action:'record'});assert.equal(r.error,true);assert.match(r.message,/1 MiB/);assert.equal(r.base64,undefined);assert(b.counts().stops>0);});
test('closing while permission is pending cancels and releases any late microphone grant',async()=>{const b=setup({late:true});const recording=b.action({action:'record'});await b.action({action:'cancel'});assert.equal((await recording).error,true);b.grant();await Promise.resolve();assert(b.counts().stops>0);assert.equal(b.counts().recorded,0);});
test('spoken readback uses the selected installed language and reports missing voices honestly',async()=>{const b=setup({voices:[{lang:'ms-MY'}]});assert.equal((await b.action({action:'speak',locale:'bm',text:'Sila sahkan.'})).error,false);assert.equal(b.counts().spoken,1);assert.equal((await setup().action({action:'speak',locale:'bm',text:'Sila sahkan.'})).error,true);});
