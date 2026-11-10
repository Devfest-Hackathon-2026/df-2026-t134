import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadString } from 'firebase/storage';
import { createTestEnv } from './setup.js';

let env;

before(async () => {
  env = await createTestEnv();
  await env.withSecurityRulesDisabled(async (context) => {
    await uploadString(ref(context.storage(), 'audio/hello.mp3'), 'fake-audio');
    await uploadString(ref(context.storage(), 'images/scenes/hello.jpg'), 'fake-image');
    await uploadString(ref(context.storage(), 'private/notes.txt'), 'secret');
  });
});

after(async () => {
  await env.clearStorage();
  await env.cleanup();
});

test('signed-in users can read audio but not upload', async () => {
  const storage = env.authenticatedContext('alice').storage();
  await assertSucceeds(getBytes(ref(storage, 'audio/hello.mp3')));
  await assertFails(uploadString(ref(storage, 'audio/evil.mp3'), 'x'));
});

test('unauthenticated users cannot read audio', async () => {
  const storage = env.unauthenticatedContext().storage();
  await assertFails(getBytes(ref(storage, 'audio/hello.mp3')));
});

test('signed-in users can read story pictures but not upload or delete them', async () => {
  const storage = env.authenticatedContext('alice').storage();
  await assertSucceeds(getBytes(ref(storage, 'images/scenes/hello.jpg')));
  await assertFails(uploadString(ref(storage, 'images/scenes/evil.jpg'), 'x'));
  await assertFails(deleteObject(ref(storage, 'images/scenes/hello.jpg')));
});

test('unauthenticated users cannot read story pictures', async () => {
  const storage = env.unauthenticatedContext().storage();
  await assertFails(getBytes(ref(storage, 'images/scenes/hello.jpg')));
});

test('paths outside audio/ and images/ are not readable', async () => {
  const storage = env.authenticatedContext('alice').storage();
  await assertFails(getBytes(ref(storage, 'private/notes.txt')));
});
