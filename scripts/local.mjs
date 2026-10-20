export const projectId = 'demo-emascare';
export const region = 'asia-southeast1';
export const hosts = {
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
};

// Check the entire environment before constructing an Admin SDK client.
export function assertLocalEnvironment(env) {
  for (const name of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'FIREBASE_PROJECT_ID']) {
    if (env[name] && env[name] !== projectId) throw new Error(`Refusing non-demo project in ${name}`);
  }
  if (env.GCLOUD_PROJECT !== projectId) throw new Error('Explicit demo project required');
  if (env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(env.FIREBASE_CONFIG); }
    catch { throw new Error('FIREBASE_CONFIG must be inline JSON for local scripts'); }
    if (config.projectId && config.projectId !== projectId) throw new Error('Refusing non-demo FIREBASE_CONFIG');
  }
  for (const [name, value] of Object.entries(hosts)) {
    if (env[name] !== value) throw new Error(`Refusing missing or non-local ${name}; expected ${value}`);
  }
  return env;
}

export function localEnvironment(source = process.env) {
  const env = {...source};
  env.GCLOUD_PROJECT ??= projectId;
  // These tools run on a developer laptop and must not probe GCE metadata.
  env.METADATA_SERVER_DETECTION = 'none';
  for (const [name, value] of Object.entries(hosts)) env[name] ??= value;
  return assertLocalEnvironment(env);
}
