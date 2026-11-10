import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { setLogLevel } from 'firebase/app';

// Denied requests are expected in these tests; keep the SDK quiet.
setLogLevel('silent');

// Run inside `firebase emulators:exec`, which sets the *_EMULATOR_HOST variables.
export async function createTestEnv() {
  const rulesDir = new URL('..', import.meta.url);
  return initializeTestEnvironment({
    projectId: 'demo-ailearn-rules',
    firestore: { rules: readFileSync(new URL('firestore.rules', rulesDir), 'utf8') },
    storage: { rules: readFileSync(new URL('storage.rules', rulesDir), 'utf8') },
  });
}
