/* Explicit user-initiated capture; bytes leave this bridge only on Prepare draft. */
(() => {
  const limit=1024*1024;
  let active=null,generation=0;
  const release=stream=>stream?.getTracks().forEach(t=>t.stop());
  const cancel=()=>{generation++;if(active){active.cancelled=true;active.abort?.();if(active.recorder?.state!=='inactive')active.recorder?.stop();release(active.stream);}};
  async function record(){
    cancel();
    const own=generation;
    if(!navigator.mediaDevices?.getUserMedia||typeof MediaRecorder==='undefined')throw new Error('Recording is unavailable. Use text or manual booking.');
    const mime=['audio/webm;codecs=opus','audio/webm','audio/ogg;codecs=opus','audio/ogg'].find(t=>MediaRecorder.isTypeSupported(t));
    if(!mime)throw new Error('No supported recording container is available. Use text or manual booking.');
    const session={stream:null,recorder:null,cancelled:false,abort:null};active=session;
    let permissionTimer,recordTimer;
    const permission=navigator.mediaDevices.getUserMedia({audio:true});
    permission.then(s=>{if(own!==generation)release(s);},()=>{});
    try{
      session.stream=await Promise.race([permission,new Promise((_,reject)=>{
        session.abort=()=>reject(new Error('Recording cancelled.'));
        permissionTimer=setTimeout(()=>{generation++;reject(new Error('Microphone permission timed out. Use manual booking or try again.'));},10000);
      })]);
      clearTimeout(permissionTimer);
      if(own!==generation||session.cancelled)throw new Error('Recording cancelled.');
      const chunks=[];let size=0,failure;
      const recorder=new MediaRecorder(session.stream,{mimeType:mime});session.recorder=recorder;
      await new Promise((resolve,reject)=>{
        session.abort=()=>{failure=new Error('Recording cancelled.');if(recorder.state!=='inactive')recorder.stop();else reject(failure);};
        recorder.ondataavailable=e=>{if(!e.data.size)return;size+=e.data.size;if(size>limit){failure=new Error('Recording is larger than 1 MiB. Record a shorter message.');if(recorder.state!=='inactive')recorder.stop();}else chunks.push(e.data);};
        recorder.onerror=()=>reject(new Error('Recording failed. Use text or manual booking.'));
        recorder.onstop=()=>failure?reject(failure):resolve();
        recordTimer=setTimeout(()=>{if(recorder.state!=='inactive')recorder.stop();},30000);
        recorder.start(250);
      });
      if(own!==generation||session.cancelled)throw new Error('Recording cancelled.');
      const actual=(recorder.mimeType||mime).split(';')[0].toLowerCase();
      if(!['audio/webm','audio/ogg'].includes(actual))throw new Error('Unsupported recording container. Use manual booking.');
      if(!size)throw new Error('No audio was captured. Try again or use manual booking.');
      const bytes=new Uint8Array(await new Blob(chunks,{type:actual}).arrayBuffer());
      if(bytes.length>limit)throw new Error('Recording is larger than 1 MiB. Record a shorter message.');
      let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
      return {mimeType:actual,base64:btoa(binary)};
    }finally{clearTimeout(permissionTimer);clearTimeout(recordTimer);release(session.stream);if(active===session)active=null;}
  }
  window.emasVoice={async action(raw){
    try{
      const c=JSON.parse(raw);let result={};
      if(c.action==='record')result=await record();
      else if(c.action==='stop'){if(active?.recorder?.state==='recording')active.recorder.stop();}
      else if(c.action==='cancel'){cancel();window.speechSynthesis?.cancel();}
      else if(c.action==='speak'){
        const speech=window.speechSynthesis;
        if(!speech)throw new Error('Speech is unavailable. You can read the request on screen.');
        const prefix=c.locale==='bm'?'ms':'en';
        const voice=speech.getVoices().find(v=>v.lang.toLowerCase().startsWith(prefix));
        if(!voice)throw new Error('No voice for this language is installed. Read the request on screen.');
        const utterance=new SpeechSynthesisUtterance(c.text);utterance.lang=c.locale==='bm'?'ms-MY':'en-MY';utterance.voice=voice;utterance.rate=0.85;
        speech.cancel();speech.speak(utterance);result.message='Read-back requested. Check that you can hear it on this device.';
      }else throw new Error('Unknown voice action.');
      return JSON.stringify({error:false,...result});
    }catch(e){return JSON.stringify({error:true,message:e.name==='NotAllowedError'?'Microphone access was denied. Use text or manual booking.':e.message||'Voice is unavailable. Use manual booking.'});}
  }};
  window.addEventListener('pagehide',cancel);
})();
