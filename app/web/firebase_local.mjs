// Configure Auth synchronously at creation, before its persisted user restores.
// FlutterFire 6.3.1 only reapplies the emulator before restore in debug mode.
// Use the same public JS SDK modules/dependencies as FlutterFire's pinned SDK.
export const firebaseSdkVersion = '13.0.0';
export const firebaseOptions = Object.freeze({
  apiKey: 'local-demo-key', appId: '1:1234567890:web:emascare-demo',
  messagingSenderId: '1234567890', projectId: 'demo-emascare',
  authDomain: 'demo-emascare.firebaseapp.com',
  databaseURL: null, storageBucket: null, measurementId: null,
});

export async function prepareLocalFirebase({
  host = window.location.hostname,
  load = (url) => import(url),
} = {}) {
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(host)) {
    throw new Error('The local demo requires a loopback origin.');
  }
  const root = `https://www.gstatic.com/firebasejs/${firebaseSdkVersion}`;
  const [core, authSdk] = await Promise.all([
    load(`${root}/firebase-app.js`), load(`${root}/firebase-auth.js`),
  ]);
  const app = core.initializeApp(firebaseOptions, 'emascare-local');
  const auth = authSdk.initializeAuth(app, {
    errorMap: authSdk.debugErrorMap,
    persistence: [authSdk.indexedDBLocalPersistence, authSdk.browserLocalPersistence, authSdk.browserSessionPersistence],
    popupRedirectResolver: authSdk.browserPopupRedirectResolver,
  });
  // No await or other Auth operation between initialization and connection.
  // The app already labels this loopback-only build throughout sign-in and
  // navigation. The SDK's fixed banner obscures phone navigation and dialogs.
  authSdk.connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
  // Finish the preconnected Auth restore before FlutterFire installs its own
  // initial-state listener. This avoids a startup race in the pinned web SDK.
  await auth.authStateReady();
}
