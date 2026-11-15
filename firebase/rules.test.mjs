import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-zira',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'tournaments/t1'), {
      hostUid: 'host', joinMode: 'open', status: 'registration',
      memberUids: ['host', 'alice'], matchUids: { m1: ['alice', 'bob'] }, data: {},
    });
    await setDoc(doc(db, 'tournaments/t1/private/host'), { draftRound: null });
    await setDoc(doc(db, 'joinCodes/ABC234'), { tid: 't1', hostUid: 'host' });
  });
});
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const claim = (uid, matchId = 'm1') => ({ matchId, uid, r: { o: 0, g1: 2, g2: 1 }, at: 1 });

test('signed-out users read nothing', () => assertFails(getDoc(doc(anon(), 'tournaments/t1'))));
test('any signed-in user can get a tournament and a join code', async () => {
  await assertSucceeds(getDoc(doc(as('zed'), 'tournaments/t1')));
  await assertSucceeds(getDoc(doc(as('zed'), 'joinCodes/ABC234')));
});
test('list only tournaments I am a member of', async () => {
  await assertSucceeds(getDocs(query(collection(as('alice'), 'tournaments'), where('memberUids', 'array-contains', 'alice'))));
  await assertFails(getDocs(collection(as('alice'), 'tournaments')));
});
test('only the host writes the tournament', async () => {
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1'), { status: 'running' }));
  await assertFails(updateDoc(doc(as('alice'), 'tournaments/t1'), { status: 'running' }));
  await assertFails(updateDoc(doc(as('host'), 'tournaments/t1'), { hostUid: 'alice' }));
});
test('create tournament only as myself', async () => {
  await assertSucceeds(setDoc(doc(as('zed'), 'tournaments/t2'), { hostUid: 'zed', memberUids: ['zed'], joinMode: 'open', status: 'registration', matchUids: {} }));
  await assertFails(setDoc(doc(as('zed'), 'tournaments/t3'), { hostUid: 'host', memberUids: ['zed'] }));
});
test('private/host only for the host', async () => {
  await assertSucceeds(getDoc(doc(as('host'), 'tournaments/t1/private/host')));
  await assertFails(getDoc(doc(as('alice'), 'tournaments/t1/private/host')));
});
test('join codes: create once, never overwrite, delete by host', async () => {
  await assertSucceeds(setDoc(doc(as('zed'), 'joinCodes/ZZZ999'), { tid: 't9', hostUid: 'zed' }));
  await assertFails(setDoc(doc(as('zed'), 'joinCodes/ABC234'), { tid: 't9', hostUid: 'zed' }));
  await assertFails(deleteDoc(doc(as('zed'), 'joinCodes/ABC234')));
  await assertSucceeds(deleteDoc(doc(as('host'), 'joinCodes/ABC234')));
});
test('entries: join only as myself, with the right status for the mode', async () => {
  await assertSucceeds(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'joined' }));
  await assertFails(setDoc(doc(as('bob'), 'tournaments/t1/entries/carol'), { displayName: 'C', status: 'joined' }));
  await assertFails(setDoc(doc(as('carol'), 'tournaments/t1/entries/carol'), { displayName: 'C', status: 'requested' }));
});
test('entries: approval mode needs requested; closedOnStart blocks after start', async () => {
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'tournaments/t1'), { joinMode: 'approval' }));
  await assertFails(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'joined' }));
  await assertSucceeds(setDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'requested' }));
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'tournaments/t1'), { joinMode: 'closedOnStart', status: 'running' }));
  await assertFails(setDoc(doc(as('dan'), 'tournaments/t1/entries/dan'), { displayName: 'Dan', status: 'joined' }));
});
test('entries: player may drop, host may approve/remove, removed cannot come back', async () => {
  await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'tournaments/t1/entries/bob'), { displayName: 'Bob', status: 'requested' }));
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { status: 'joined' }));
  await assertSucceeds(updateDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { status: 'dropped' }));
  await assertSucceeds(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { status: 'removed' }));
  await assertFails(updateDoc(doc(as('bob'), 'tournaments/t1/entries/bob'), { status: 'joined' }));
  await assertFails(updateDoc(doc(as('host'), 'tournaments/t1/entries/bob'), { displayName: 'X' }));
});
test('claims: only my own, only on my published match', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'tournaments/t1/claims/m1_alice'), claim('alice')));
  await assertFails(setDoc(doc(as('alice'), 'tournaments/t1/claims/m1_bob'), claim('bob')));
  await assertFails(setDoc(doc(as('carol'), 'tournaments/t1/claims/m1_carol'), claim('carol')));
  await assertFails(setDoc(doc(as('alice'), 'tournaments/t1/claims/m2_alice'), claim('alice', 'm2')));
});
test('claims readable by members and host only', async () => {
  await assertSucceeds(getDocs(collection(as('alice'), 'tournaments/t1/claims')));
  await assertSucceeds(getDocs(collection(as('host'), 'tournaments/t1/claims')));
  await assertFails(getDocs(collection(as('zed'), 'tournaments/t1/claims')));
});
test('users: write only my own', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'users/alice'), { displayName: 'A' }));
  await assertFails(setDoc(doc(as('alice'), 'users/bob'), { displayName: 'B' }));
});
