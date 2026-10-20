const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/preview_bridge.js'), 'utf8');
function setup({ denied = false, supported = true, voices = [] } = {}) {
  let stops = 0, recordings = 0, played = 0, spoken = 0;
  const stream = { getTracks: () => [{ stop: () => stops++ }] };
  class Recorder {
    static isTypeSupported() { return true; }
    constructor() { this.mimeType='audio/webm';this.state='inactive'; }
    start() { this.state='recording'; recordings++; }
    stop() { this.state='inactive';this.ondataavailable({data:new Blob(['sample'])});this.onstop(); }
  }
  const context = {
    window: {
      isSecureContext:true, matchMedia:()=>({matches:false}),addEventListener:()=>{},
      speechSynthesis:{getVoices:()=>voices,cancel:()=>{},speak:()=>spoken++},
    },
    navigator: {
      permissions:{query:async()=>({state:denied?'denied':'prompt'})},
      mediaDevices:supported?{getUserMedia:async()=>{if(denied) {const e=new Error('denied');e.name='NotAllowedError';throw e;}return stream;}}:undefined,
    },
    MediaRecorder:Recorder, Blob, URL:{createObjectURL:()=> 'blob:local-test',revokeObjectURL:()=>{}},
    Audio:class { async play() {played++;} pause() {} },
    SpeechSynthesisUtterance:class {constructor(text) {this.text=text;}},
    setTimeout:(fn,ms)=>setTimeout(fn,ms===5000?0:ms), clearTimeout,
  };
  vm.runInNewContext(source,context);
  return {action:async(name)=>JSON.parse(await context.window.emasPreview.action(name)),counts:()=>({stops,recordings,played,spoken})};
}
test('Capability check does not request microphone access',async()=>{
  const b=setup();const result=await b.action('check');
  assert.equal(result.secure,true);assert.equal(result.permission,'prompt');assert.equal(result.recorded,false);
  assert.equal(b.counts().recordings,0);
});
test('Denied microphone leaves a recoverable message',async()=>{
  const b=setup({denied:true});const result=await b.action('record');
  assert.equal(result.error,true);assert.match(result.message,/denied/);assert.equal(result.recorded,false);
});
test('Local recording releases tracks and can be replayed',async()=>{
  const b=setup();const result=await b.action('record');
  assert.equal(result.recorded,true);assert.equal(b.counts().stops,1);
  await b.action('play');assert.equal(b.counts().played,1);
});
test('Missing APIs and missing installed voices are reported without a false success',async()=>{
  const b=setup({supported:false});assert.equal((await b.action('record')).error,true);
  const result=await b.action('speak-bm');assert.equal(result.error,true);assert.match(result.message,/No speech voices/);
});
test('Read-back uses an installed language voice',async()=>{
  const b=setup({voices:[{lang:'ms-MY'}]});const result=await b.action('speak-bm');
  assert.equal(result.error,false);assert.equal(b.counts().spoken,1);
});
