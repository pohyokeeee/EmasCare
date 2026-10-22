const {test} = require('node:test');
const assert = require('node:assert/strict');

test('Auth emulator connects immediately after initialization with matching FlutterFire dependencies', async () => {
  const {prepareLocalFirebase} = await import('../web/firebase_local.mjs');
  const calls = [];
  const localAuth = {async authStateReady() { calls.push('ready'); }};
  const authSdk = {
    indexedDBLocalPersistence: {}, browserLocalPersistence: {}, browserSessionPersistence: {},
    browserPopupRedirectResolver: {}, debugErrorMap: {},
    initializeAuth(app, options) {
      calls.push('initialize');
      assert.equal(app, 'app');
      assert.deepEqual(options.persistence, [authSdk.indexedDBLocalPersistence, authSdk.browserLocalPersistence, authSdk.browserSessionPersistence]);
      return localAuth;
    },
    connectAuthEmulator(auth, url, options) { calls.push('connect'); assert.equal(auth, localAuth); assert.equal(url, 'http://127.0.0.1:9099'); assert.deepEqual(options, {disableWarnings:true}); },
  };
  const core = {initializeApp(options, name) {
    assert.deepEqual(options, {
      apiKey:'local-demo-key', appId:'1:1234567890:web:emascare-demo', messagingSenderId:'1234567890',
      projectId:'demo-emascare', authDomain:'demo-emascare.firebaseapp.com',
      databaseURL:null, storageBucket:null, measurementId:null,
    });
    assert.equal(name, 'emascare-local'); return 'app';
  }};
  await prepareLocalFirebase({host:'127.0.0.1', load:async (url) => url.endsWith('/firebase-app.js') ? core : authSdk});
  assert.deepEqual(calls, ['initialize', 'connect', 'ready']);
});

test('non-loopback origins fail before any SDK loads or Auth operations', async () => {
  const {prepareLocalFirebase} = await import('../web/firebase_local.mjs');
  let loaded = false;
  await assert.rejects(prepareLocalFirebase({host:'example.com', load:async () => { loaded = true; }}), /loopback/);
  assert.equal(loaded, false);
});
