import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {Timestamp} from 'firebase-admin/firestore';
const require=createRequire(import.meta.url);
const {voiceInput,validateVoiceResult,geminiProvider}=require('../functions/lib/voice.js');
const {progressPeriod,sanitizeAvailability}=require('../functions/lib/summaries.js');
const {instant,createOperationsService}=require('../functions/lib/operations.js');
const reason=(r)=>(e)=>e.details?.reason===r;
const context={locale:'en',now:'2026-10-22T00:00:00.000Z',localDate:'2026-10-22',input:{type:'text',text:'Walk with me at the garden activity tomorrow'},
  activities:[{id:'garden',placeId:'park',title:{en:'Garden walk',bm:'Jalan di taman'},startsAt:'2026-10-23T01:00:00.000Z',endsAt:'2026-10-23T02:00:00.000Z'}],places:[{id:'park',name:'Garden'}]};
const extraction={transcript:context.input.text,draft:{activityId:'garden',placeId:null,startsAt:null,endsAt:null,taskType:'walk_with_me',preferredLanguage:'en',preferredHelperGender:'any'}};

test('Malaysia progress periods use local Monday/month, including year rollover and end-exclusive bounds',()=>{
  const at=Timestamp.fromDate(new Date('2026-12-31T16:00:00Z'));
  assert.deepEqual(progressPeriod('week',null,at),{periodKey:'2026-12-28',start:Date.parse('2026-12-27T16:00:00Z'),end:Date.parse('2027-01-03T16:00:00Z')});
  assert.deepEqual(progressPeriod('month',null,at),{periodKey:'2027-01',start:Date.parse('2026-12-31T16:00:00Z'),end:Date.parse('2027-01-31T16:00:00Z')});
  for(const [type,key] of [['day',null],['week','2026-10-22'],['week','2026-02-30'],['month','2026-13'],['month',1]])assert.throws(()=>progressPeriod(type,key,at),reason('INVALID_PERIOD'));
});
test('availability suppresses under five distinct helpers, strips IDs, rejects overlapping cohort membership',()=>{
  const cell={weekday:4,startMinute:540,endMinute:660,cohort:'retiree',requestIds:['a','a','b']};
  const input={townshipId:'t',isDemo:true,updatedAt:Timestamp.now(),cells:[{...cell,helperIds:['a','b','c','d','d']}]};
  const small=sanitizeAvailability(input);assert.equal(small.cells[0].helperCount,null);assert.equal(small.cells[0].requestCount,null);assert.equal(small.cells[0].suppressed,true);
  input.cells[0].helperIds.push('e');const big=sanitizeAvailability(input);assert.equal(big.cells[0].helperCount,5);assert.equal(big.cells[0].requestCount,2);assert.equal(JSON.stringify(big).includes('helperIds'),false);
  assert.throws(()=>sanitizeAvailability({...input,cells:[input.cells[0],{...input.cells[0],cohort:'student'}]}),reason('INVALID_SUMMARY_INPUT'));
});
test('voice input enforces exact shape, canonical bounded base64 and supported MIME',()=>{
  assert.deepEqual(voiceInput({type:'text',text:' Help '}),{type:'text',text:'Help'});
  assert.deepEqual(voiceInput({type:'audio',mimeType:'audio/webm',base64:'YWJj'}),{type:'audio',mimeType:'audio/webm',base64:'YWJj'});
  for(const base64 of ['', 'a', 'ab==','YWJj\n',Buffer.alloc(1048577).toString('base64')])assert.throws(()=>voiceInput({type:'audio',mimeType:'audio/wav',base64}),reason('INVALID_AUDIO'));
  assert.equal(voiceInput({type:'audio',mimeType:'audio/wav',base64:Buffer.alloc(1048576).toString('base64')}).type,'audio');
  assert.throws(()=>voiceInput({type:'audio',mimeType:'video/mp4',base64:'YWJj'}),reason('UNSUPPORTED_AUDIO_TYPE'));
  assert.throws(()=>voiceInput({type:'text',text:'x',elderId:'spoof'}),reason('UNSUPPORTED_AUDIO_TYPE'));
});
test('voice draft uses trusted catalog schedule, server elder identity, and requires explicit confirmation',()=>{
  const result=validateVoiceResult(extraction,context,'elder');assert.equal(result.canConfirm,true);assert.equal(result.draft.elderId,'elder');
  assert.equal(result.draft.startsAt,context.activities[0].startsAt);assert.equal(result.draft.placeId,'park');assert.deepEqual(result.missingFields,[]);
  assert.match(result.readBackText,/MYT/);assert.match(result.readBackText,/confirm/);
  assert.throws(()=>validateVoiceResult({...extraction,draft:{...extraction.draft,elderId:'spoof'}},context,'elder'),reason('VOICE_INVALID_RESPONSE'));
  assert.throws(()=>validateVoiceResult({transcript:'x',draft:[],canConfirm:true},context,'elder'),reason('VOICE_INVALID_RESPONSE'));
});
test('unknown activity, vague place, unsupported task, past/fractional times become clarification',()=>{
  const result=validateVoiceResult({transcript:'x',draft:{activityId:'hallucination',placeId:'outside',taskType:'tanya_dulu',startsAt:'2026-10-20T00:00:00Z',endsAt:'2026-10-23T01:00:00.001Z'}},context,'elder');
  assert.equal(result.canConfirm,false);assert.deepEqual(new Set(result.missingFields),new Set(['activityId','placeId','taskType','startsAt','endsAt']));
  assert.equal(result.draft.preferredLanguage,'en');assert.equal(result.draft.preferredHelperGender,'any');
  const phone=validateVoiceResult({transcript:'Help me by phone tomorrow from nine to ten',draft:{taskType:'phone_help',activityId:null,placeId:null,startsAt:'2026-10-23T01:00:00Z',endsAt:'2026-10-23T02:00:00Z'}},context,'elder');
  assert.equal(phone.canConfirm,true);assert.equal(phone.draft.placeId,null);
});
test('Gemini transport is disabled without explicit configuration; credentials stay in header and failures are sanitized',async()=>{
  let count=0;const transport=async(url,options)=>{count++;assert.equal(url.includes('secret-test-key'),false);assert.equal(options.headers['x-goog-api-key'],'secret-test-key');
    const request=JSON.parse(options.body);assert.equal(request.generationConfig.responseMimeType,'application/json');assert.equal(request.contents[0].parts[0].text,context.input.text);
    assert.equal(JSON.stringify(request).includes('elder_demo'),false);
    return new Response(JSON.stringify({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(extraction)}]}}]}));};
  await assert.rejects(geminiProvider({},transport)(context),reason('VOICE_SERVICE_UNAVAILABLE'));assert.equal(count,0);
  const env={GEMINI_ENABLED:'true',GEMINI_API_KEY:'secret-test-key',GEMINI_MODEL:'configured-test-model'};
  assert.deepEqual(await geminiProvider(env,transport)(context),extraction);assert.equal(count,1);
  for(const [status,error] of [[429,'VOICE_RATE_LIMIT'],[503,'VOICE_SERVICE_UNAVAILABLE']])await assert.rejects(geminiProvider(env,async()=>new Response('sensitive provider text',{status}))(context),reason(error));
  await assert.rejects(geminiProvider(env,async()=>{throw Object.assign(new Error('private'),{name:'TimeoutError'});})(context),reason('VOICE_TIMEOUT'));
  await assert.rejects(geminiProvider(env,async()=>new Response(JSON.stringify({candidates:[{finishReason:'MAX_TOKENS'}]})))(context),reason('VOICE_INVALID_RESPONSE'));
  const audio={...context,input:{type:'audio',mimeType:'audio/webm',base64:'YWJj'}};
  await geminiProvider(env,async(_url,options)=>{assert.deepEqual(JSON.parse(options.body).contents[0].parts[0],{inlineData:{mimeType:'audio/webm',data:'YWJj'}});return new Response(JSON.stringify({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(extraction)}]}}]}));})(audio);
});
test('warning and report validation rejects invalid dates, unsupported report intents and client-controlled metadata',async()=>{
  assert.equal(instant('2026-10-23T01:00:01Z').toMillis(),Date.parse('2026-10-23T01:00:01Z'));
  for(const date of ['2026-02-30T00:00:00Z','tomorrow','0000-01-01T00:00:00Z'])assert.throws(()=>instant(date),reason('INVALID_TIME_RANGE'));
  const service=createOperationsService({}),input={contractVersion:1,idempotencyKey:'v',kind:'tanya_dulu',text:'x'};
  await assert.rejects(service.submitReport('elder',input),reason('UNSUPPORTED_REPORT_KIND'));
  await assert.rejects(service.submitReport('elder',{...input,kind:'place_problem',placeId:'place',state:'done'}),reason('UNKNOWN_FIELD'));
  await assert.rejects(service.setPlaceWarning('coord',{contractVersion:1,idempotencyKey:'v',placeId:'place',warning:{level:'safe',text:'all clear',expiresAt:'2026-10-23T00:00:00Z'}}),reason('INVALID_WARNING'));
});
