/* Local device smoke check. No backend, analytics, upload or persistent audio. */
(() => {
  let recordingUrl = null;
  let audio = null;
  let activeStream = null;
  const state = { recorded: false };
  const stopTracks = (stream) => stream?.getTracks().forEach((track) => track.stop());
  const media = (query) => window.matchMedia?.(query).matches === true;
  async function check() {
    let permission = 'not available';
    try { permission = (await navigator.permissions.query({ name: 'microphone' })).state; } catch (_) { /* Safari may not support this query. */ }
    return {
      secure: window.isSecureContext === true,
      microphone: !!navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== 'undefined',
      speech: 'speechSynthesis' in window,
      permission,
      recorded: state.recorded,
      reducedMotion: media('(prefers-reduced-motion: reduce)'),
      reducedTransparency: media('(prefers-reduced-transparency: reduce)'),
      highContrast: media('(prefers-contrast: more)'),
    };
  }
  async function record() {
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      throw new Error('Recording is unavailable. Use localhost or HTTPS and a supported browser.');
    }
    let permissionTimedOut = false;
    let permissionTimer;
    const streamPromise = navigator.mediaDevices.getUserMedia({ audio: true });
    // If permission arrives after the timeout, immediately release the microphone.
    streamPromise.then((stream) => { if (permissionTimedOut) stopTracks(stream); }, () => {});
    let stream;
    try {
      stream = await Promise.race([
        streamPromise,
        new Promise((_, reject) => { permissionTimer = setTimeout(() => {
          permissionTimedOut = true;
          reject(new Error('Microphone permission timed out. Allow access and try again.'));
        }, 10000); }),
      ]);
    } finally { clearTimeout(permissionTimer); }
    activeStream = stream;
    try {
      const chunks = [];
      const preferred = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'].find((mime) => MediaRecorder.isTypeSupported(mime));
      const recorder = new MediaRecorder(stream, preferred ? { mimeType: preferred } : {});
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => { if (recorder.state !== 'inactive') recorder.stop(); }, 5000);
        recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
        recorder.onerror = () => { clearTimeout(timer); reject(new Error('Recording failed. Please try again.')); };
        recorder.onstop = () => { clearTimeout(timer); resolve(); };
        recorder.start();
      });
      if (!chunks.length) throw new Error('No audio was captured. Please check your microphone.');
      if (audio) { audio.pause(); audio = null; }
      if (recordingUrl) URL.revokeObjectURL(recordingUrl);
      const blob = new Blob(chunks, { type: recorder.mimeType });
      recordingUrl = URL.createObjectURL(blob);
      state.recorded = true;
      return 'Recorded 5 seconds locally. Play it back to check the sound.';
    } finally { stopTracks(stream); activeStream = null; }
  }
  window.emasPreview = {
    async action(action) {
      let message = 'Browser APIs checked. Recording and audible playback still need a device test.';
      let error = false;
      try {
        if (action === 'record') message = await record();
        else if (action === 'play') {
          if (!recordingUrl) throw new Error('Record a short clip first.');
          audio?.pause();
          audio = new Audio(recordingUrl);
          await audio.play();
          message = 'Playing your local recording. No audio is uploaded.';
        } else if (action.startsWith('speak-')) {
          if (!('speechSynthesis' in window)) throw new Error('Spoken read-back is unavailable in this browser.');
          const bm = action === 'speak-bm';
          const utterance = new SpeechSynthesisUtterance(bm ? 'Tai chi esok pukul sepuluh pagi. Ini ujian suara sahaja.' : 'Tai chi tomorrow at ten in the morning. This is only a voice test.');
          utterance.lang = bm ? 'ms-MY' : 'en-MY';
          utterance.rate = 0.85;
          const voices = window.speechSynthesis.getVoices();
          if (!voices.length) throw new Error('No speech voices are available on this device. Try your presentation browser.');
          const voice = voices.find((v) => v.lang.toLowerCase().startsWith(bm ? 'ms' : 'en'));
          if (!voice) throw new Error(bm ? 'No Malay voice is installed. Try English or install a Malay voice.' : 'No English voice is installed on this device.');
          utterance.voice = voice;
          window.speechSynthesis.cancel();
          window.speechSynthesis.speak(utterance);
          message = 'Spoken test requested. Check that you can hear it on this device.';
        }
      } catch (e) {
        error = true;
        message = e.name === 'NotAllowedError' ? 'Microphone access was denied. Allow it in browser settings to test recording; the rest of the preview still works.' : e.name === 'NotFoundError' ? 'No microphone was found. Try a device with a microphone.' : (e.message || 'Device check failed. Please try again.');
      }
      return JSON.stringify({ ...(await check()), error, message });
    },
  };
  window.addEventListener('pagehide', () => {
    stopTracks(activeStream);
    audio?.pause();
    window.speechSynthesis?.cancel();
    if (recordingUrl) URL.revokeObjectURL(recordingUrl);
  });
})();
