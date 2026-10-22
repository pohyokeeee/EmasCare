import {spawn, spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {localEnvironment, projectId} from './local.mjs';

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2];
if (!['start','test','coordination-test'].includes(mode)) throw new Error('Use: node scripts/emulators.mjs start|test|coordination-test');
const env = {...localEnvironment(), FIREBASE_CLI_DISABLE_UPDATE_CHECK:'true'};
if (process.platform === 'win32') {
  // Oracle's javapath redirector launches another java.exe. Killing that
  // redirector can leave the actual emulator alive after Firebase exits.
  // Prefer the real JDK binary for this child process, without changing PATH
  // or Java settings globally on the developer's computer.
  if (!env.JAVA_HOME) {
    const java = spawnSync('java',['-XshowSettings:properties','-version'],{encoding:'utf8'});
    if (java.error || java.status !== 0) throw new Error('A Java JDK is required for the Firestore emulator');
    env.JAVA_HOME = java.stderr.match(/^\s*java\.home\s*=\s*(.+)$/m)?.[1]?.trim();
  }
  if (!env.JAVA_HOME || !existsSync(resolve(env.JAVA_HOME,'bin','java.exe'))) {
    throw new Error('Set JAVA_HOME to the installed Java JDK directory');
  }
  const pathKey = Object.keys(env).find((name) => name.toUpperCase() === 'PATH') ?? 'PATH';
  env[pathKey] = `${resolve(env.JAVA_HOME,'bin')};${env[pathKey] ?? ''}`;
}
// npm scripts use the pinned local Node 22 binary; children inherit that runtime.
if (Number(process.versions.node.split('.')[0]) !== 22) throw new Error('Run through npm scripts to use the pinned local Node 22 runtime');
const args = mode === 'start'
  ? ['emulators:start','--project',projectId,'--only','auth,firestore,functions']
  : ['emulators:exec','--project',projectId,'--only','auth,firestore,functions',mode === 'test' ? 'npm run test:integration' : 'node --test --test-concurrency=1 tests/coordination.test.mjs tests/membership.test.mjs'];
const child = spawn(process.execPath, [require.resolve('firebase-tools/lib/bin/firebase.js'),...args], {cwd:root, env, stdio:'inherit'});
child.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code) => { process.exitCode = code ?? 1; });
