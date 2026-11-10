import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';
import { createTestEnv } from './setup.js';

let env;

const profile = (overrides = {}) => ({
  displayName: 'たろう',
  grade: 'j2',
  createdAt: serverTimestamp(),
  ...overrides,
});

// Writes as the server / content tools (rules are bypassed).
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

before(async () => {
  env = await createTestEnv();
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

describe('users/{uid}', () => {
  test('the owner can create a valid profile', async () => {
    const db = env.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(db, 'users/alice'), profile()));
  });

  test('another user cannot create or read the profile', async () => {
    const bob = env.authenticatedContext('bob').firestore();
    await assertFails(setDoc(doc(bob, 'users/alice'), profile()));
    await seed('users/alice', { displayName: 'たろう', grade: 'j2', createdAt: new Date() });
    await assertFails(getDoc(doc(bob, 'users/alice')));
  });

  test('unauthenticated users cannot read profiles', async () => {
    await seed('users/alice', { displayName: 'たろう', grade: 'j2', createdAt: new Date() });
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users/alice')));
  });

  test('extra fields such as xp are rejected', async () => {
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(db, 'users/alice'), profile({ xp: 9999 })));
  });

  test('invalid grade, empty or long nickname are rejected', async () => {
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(db, 'users/alice'), profile({ grade: 'university' })));
    await assertFails(setDoc(doc(db, 'users/alice'), profile({ displayName: '   ' })));
    await assertFails(setDoc(doc(db, 'users/alice'), profile({ displayName: 'あ'.repeat(21) })));
  });

  test('createdAt cannot be chosen by the client or changed later', async () => {
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(db, 'users/alice'), profile({ createdAt: new Date(2000, 0, 1) })));

    await assertSucceeds(setDoc(doc(db, 'users/alice'), profile()));
    await assertSucceeds(updateDoc(doc(db, 'users/alice'), { displayName: 'じろう' }));
    await assertFails(updateDoc(doc(db, 'users/alice'), { createdAt: new Date(2000, 0, 1) }));
  });
});

describe('server-written documents', () => {
  test('the owner can read but not write progress', async () => {
    await seed('progress/alice', { xp: 10, streakDays: 1 });
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'progress/alice')));
    await assertFails(setDoc(doc(alice, 'progress/alice'), { xp: 9999, streakDays: 99 }));
    await assertFails(getDoc(doc(env.authenticatedContext('bob').firestore(), 'progress/alice')));
  });

  test('the owner can read but not write attempts', async () => {
    await seed('attempts/alice/items/a1', { exerciseId: 'u1-l1-q1', correct: true });
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'attempts/alice/items/a1')));
    await assertFails(setDoc(doc(alice, 'attempts/alice/items/a2'), { correct: true }));
    await assertFails(
      getDoc(doc(env.authenticatedContext('bob').firestore(), 'attempts/alice/items/a1')),
    );
  });
});

describe('teaching material', () => {
  for (const path of ['units/u1', 'lessons/u1-l1', 'exercises/u1-l1-q1']) {
    test(`${path} is readable when signed in and never writable by clients`, async () => {
      await seed(path, { title: 'x' });
      const db = env.authenticatedContext('alice').firestore();
      await assertSucceeds(getDoc(doc(db, path)));
      await assertFails(setDoc(doc(db, path), { title: 'changed' }));
      await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path)));
    });
  }

  test('answer keys and drafts are never readable by clients', async () => {
    await seed('answerKeys/u1-l1-q1', { type: 'choice', correctOptionId: 'a' });
    await seed('exerciseDrafts/d1', { status: 'draft' });
    const db = env.authenticatedContext('alice').firestore();
    await assertFails(getDoc(doc(db, 'answerKeys/u1-l1-q1')));
    await assertFails(getDoc(doc(db, 'exerciseDrafts/d1')));
  });
});
