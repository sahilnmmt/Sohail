// Security rules tests against the Firestore emulator.
// Run: npm run test:rules
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
  type Firestore,
} from 'firebase/firestore';

let env: RulesTestEnvironment;
const FAMILY = 'Fam0123456789AB';
const CODE = 'ABCDEFGH23';

const as = (uid: string): Firestore => env.authenticatedContext(uid).firestore() as unknown as Firestore;
const anon = (): Firestore => env.unauthenticatedContext().firestore() as unknown as Firestore;
const days = (n: number) => Timestamp.fromMillis(Date.now() + n * 86_400_000);

async function createFamily(db: Firestore, uid: string, id = FAMILY, name = 'The Khans') {
  const b = writeBatch(db);
  b.set(doc(db, 'families', id), { name, ownerUid: uid, createdAt: serverTimestamp() });
  b.set(doc(db, 'families', id, 'members', uid), { uid, role: 'owner', displayName: 'Owner', joinedAt: serverTimestamp() });
  return b.commit();
}

function invite(db: Firestore, code = CODE, role = 'adult', expiresAt = days(3), by = 'owner') {
  return setDoc(doc(db, 'invites', code), {
    familyId: FAMILY, familyName: 'The Khans', role, createdBy: by, createdAt: serverTimestamp(), expiresAt,
  });
}

function join(db: Firestore, uid: string, role = 'adult', code = CODE) {
  return setDoc(doc(db, 'families', FAMILY, 'members', uid), {
    uid, role, displayName: uid, joinedAt: serverTimestamp(), invite: code,
  });
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sohail',
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
afterAll(() => env.cleanup());
beforeEach(() => env.clearFirestore());

/** owner + adult "dad" + child "kid" in FAMILY, via real rule-checked writes. */
async function seedFamily() {
  await createFamily(as('owner'), 'owner');
  await invite(as('owner'), CODE, 'adult');
  await join(as('dad'), 'dad', 'adult');
  await invite(as('owner'), 'KDSCHLD234', 'child');
  await join(as('kid'), 'kid', 'child', 'KDSCHLD234');
}

describe('profiles', () => {
  it('only you can read and write your profile', async () => {
    const mine = doc(as('alice'), 'users', 'alice');
    await assertSucceeds(setDoc(mine, { displayName: 'Alice', email: 'a@x.io', createdAt: serverTimestamp() }));
    await assertSucceeds(getDoc(mine));
    await assertFails(getDoc(doc(as('bob'), 'users', 'alice')));
    await assertFails(setDoc(doc(as('bob'), 'users', 'alice'), { displayName: 'Hacked' }));
    await assertFails(getDoc(doc(anon(), 'users', 'alice')));
  });

  it('rejects unknown fields and bad names', async () => {
    const mine = doc(as('alice'), 'users', 'alice');
    await assertFails(setDoc(mine, { displayName: 'A', admin: true }));
    await assertFails(setDoc(mine, { displayName: '' }));
    await assertFails(setDoc(mine, { displayName: 'x'.repeat(41) }));
  });
});

describe('families', () => {
  it('a signed-in user creates a family and becomes its owner', async () => {
    await assertSucceeds(createFamily(as('owner'), 'owner'));
    const f = await getDoc(doc(as('owner'), 'families', FAMILY));
    expect(f.data()?.ownerUid).toBe('owner');
  });

  it('cannot create a family without the owner record, for someone else, or with a bad id', async () => {
    const db = as('owner');
    await assertFails(setDoc(doc(db, 'families', FAMILY), { name: 'X', ownerUid: 'owner', createdAt: serverTimestamp() }));
    const b = writeBatch(db);
    b.set(doc(db, 'families', FAMILY), { name: 'X', ownerUid: 'someone', createdAt: serverTimestamp() });
    b.set(doc(db, 'families', FAMILY, 'members', 'owner'), { uid: 'owner', role: 'owner', displayName: 'O', joinedAt: serverTimestamp() });
    await assertFails(b.commit());
    await assertFails(createFamily(db, 'owner', 'bad/id'.replace('/', '_') + '!'));
    await assertFails(createFamily(anon(), 'owner'));
  });

  it('cannot take over an existing family by "founding" it again', async () => {
    await createFamily(as('owner'), 'owner');
    await assertFails(createFamily(as('mallory'), 'mallory'));
    await assertFails(setDoc(doc(as('mallory'), 'families', FAMILY, 'members', 'mallory'),
      { uid: 'mallory', role: 'owner', displayName: 'M', joinedAt: serverTimestamp() }));
  });

  it('only members can read; only the owner can rename or delete', async () => {
    await seedFamily();
    await assertSucceeds(getDoc(doc(as('dad'), 'families', FAMILY)));
    await assertSucceeds(getDoc(doc(as('kid'), 'families', FAMILY)));
    await assertFails(getDoc(doc(as('stranger'), 'families', FAMILY)));
    await assertFails(updateDoc(doc(as('dad'), 'families', FAMILY), { name: 'Dads' }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY), { ownerUid: 'dad' }));
    await assertSucceeds(updateDoc(doc(as('owner'), 'families', FAMILY), { name: 'Khan family' }));
    await assertFails(deleteDoc(doc(as('dad'), 'families', FAMILY)));
  });

  it('the owner sets valid message-server settings; others cannot', async () => {
    await seedFamily();
    const server = { host: '192.168.1.25', port: 1883, tls: false };
    await assertSucceeds(updateDoc(doc(as('owner'), 'families', FAMILY), { server }));
    await assertFails(updateDoc(doc(as('dad'), 'families', FAMILY), { server }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY), { server: { ...server, port: 70000 } }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY), { server: { ...server, port: '1883' } }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY), { server: { ...server, user: 'x' } }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY), { server: { ...server, host: '' } }));
  });

  it('the owner deletes the whole family in one batch', async () => {
    await seedFamily();
    const db = as('owner');
    const b = writeBatch(db);
    b.delete(doc(db, 'families', FAMILY, 'members', 'dad'));
    b.delete(doc(db, 'families', FAMILY, 'members', 'kid'));
    b.delete(doc(db, 'invites', CODE));
    b.delete(doc(db, 'families', FAMILY));
    b.delete(doc(db, 'families', FAMILY, 'members', 'owner'));
    await assertSucceeds(b.commit());
  });
});

describe('members and invites', () => {
  it('joins with a valid invite, with exactly the invited role', async () => {
    await createFamily(as('owner'), 'owner');
    await invite(as('owner'), CODE, 'child');
    await assertFails(join(as('kid'), 'kid', 'adult'));
    await assertFails(join(as('kid'), 'kid', 'owner'));
    await assertSucceeds(join(as('kid'), 'kid', 'child'));
  });

  it('rejects joining without an invite, with a wrong or expired code, or as someone else', async () => {
    await createFamily(as('owner'), 'owner');
    await assertFails(setDoc(doc(as('eve'), 'families', FAMILY, 'members', 'eve'),
      { uid: 'eve', role: 'adult', displayName: 'Eve', joinedAt: serverTimestamp() }));
    await assertFails(join(as('eve'), 'eve', 'adult', 'ZZZZZZZZZZ'));
    await assertFails(join(as('eve'), 'bob', 'adult'));

    // An expired invite (written directly, bypassing rules, to simulate time passing).
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore() as unknown as Firestore, 'invites', 'LDCDEXY234'), {
        familyId: FAMILY, familyName: 'The Khans', role: 'adult', createdBy: 'owner',
        createdAt: Timestamp.fromMillis(Date.now() - 9 * 86_400_000), expiresAt: Timestamp.fromMillis(Date.now() - 60_000),
      });
    });
    await assertFails(join(as('eve'), 'eve', 'adult', 'LDCDEXY234'));
  });

  it('an invite for one family cannot be used to join another', async () => {
    await createFamily(as('owner'), 'owner');
    await createFamily(as('other'), 'other', 'OtherFamily12345', 'Others');
    await invite(as('owner'), CODE, 'adult');
    await assertFails(setDoc(doc(as('eve'), 'families', 'OtherFamily12345', 'members', 'eve'),
      { uid: 'eve', role: 'adult', displayName: 'Eve', joinedAt: serverTimestamp(), invite: CODE }));
  });

  it('who may create invites, and their limits', async () => {
    await seedFamily();
    await assertSucceeds(invite(as('dad'), 'DADSCDE234', 'child', days(1), 'dad'));
    await assertFails(invite(as('kid'), 'KDSTRY2345', 'child', days(1), 'kid'));
    await assertFails(invite(as('stranger'), 'STRNGR2345', 'adult', days(1), 'stranger'));
    await assertFails(invite(as('owner'), 'WNRCDE2345', 'owner', days(1)));
    await assertFails(invite(as('owner'), 'LNGCDE2345', 'adult', days(8)));
    await assertFails(invite(as('owner'), 'short', 'adult', days(1)));
    await assertFails(invite(as('owner'), 'IOCODE0123', 'adult', days(1))); // ambiguous I/O/0/1 not allowed
  });

  it('invite codes can be read by code but not listed by outsiders', async () => {
    await seedFamily();
    await assertSucceeds(getDoc(doc(as('stranger'), 'invites', CODE)));
    await assertFails(getDocs(collection(as('stranger'), 'invites')));
    await assertFails(getDocs(query(collection(as('stranger'), 'invites'), where('familyId', '==', FAMILY))));
    await assertSucceeds(getDocs(query(collection(as('owner'), 'invites'), where('familyId', '==', FAMILY))));
    await assertFails(getDocs(query(collection(as('kid'), 'invites'), where('familyId', '==', FAMILY))));
    await assertFails(getDoc(doc(anon(), 'invites', CODE)));
  });

  it('role changes, renames, leaving and removal', async () => {
    await seedFamily();
    await assertSucceeds(updateDoc(doc(as('dad'), 'families', FAMILY, 'members', 'dad'), { displayName: 'Abu' }));
    await assertFails(updateDoc(doc(as('dad'), 'families', FAMILY, 'members', 'dad'), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('dad'), 'families', FAMILY, 'members', 'kid'), { role: 'adult' }));
    await assertSucceeds(updateDoc(doc(as('owner'), 'families', FAMILY, 'members', 'kid'), { role: 'adult' }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY, 'members', 'kid'), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('owner'), 'families', FAMILY, 'members', 'owner'), { role: 'adult' }));

    await assertFails(deleteDoc(doc(as('dad'), 'families', FAMILY, 'members', 'kid')));
    await assertSucceeds(deleteDoc(doc(as('kid'), 'families', FAMILY, 'members', 'kid'))); // leave
    await assertSucceeds(deleteDoc(doc(as('owner'), 'families', FAMILY, 'members', 'dad'))); // remove
    await assertFails(deleteDoc(doc(as('owner'), 'families', FAMILY, 'members', 'owner'))); // owner can't orphan the family
    await assertFails(getDoc(doc(as('dad'), 'families', FAMILY))); // removed members lose access
  });

  it('the uid field must be your own', async () => {
    await createFamily(as('owner'), 'owner');
    await invite(as('owner'), CODE, 'adult');
    await assertFails(setDoc(doc(as('eve'), 'families', FAMILY, 'members', 'eve'),
      { uid: 'owner', role: 'adult', displayName: 'Eve', joinedAt: serverTimestamp(), invite: CODE }));
  });

  it('"my families" collection-group query only returns your own memberships', async () => {
    await seedFamily();
    await createFamily(as('owner'), 'owner', 'SecondFamily1234', 'Work');
    const mine = await assertSucceeds(
      getDocs(query(collectionGroup(as('owner'), 'members'), where('uid', '==', 'owner'))));
    expect(mine.docs.map((d) => d.ref.parent.parent!.id).sort()).toEqual([FAMILY, 'SecondFamily1234'].sort());
    await assertFails(getDocs(query(collectionGroup(as('stranger'), 'members'), where('uid', '==', 'owner'))));
    await assertFails(getDocs(collectionGroup(as('stranger'), 'members')));
  });

  it('members see each other; outsiders do not', async () => {
    await seedFamily();
    await assertSucceeds(getDocs(collection(as('kid'), 'families', FAMILY, 'members')));
    await assertFails(getDocs(collection(as('stranger'), 'families', FAMILY, 'members')));
  });
});

describe('robots', () => {
  const robot = (db: Firestore, id = 'sohail-a1b2c3', by = 'owner', familyId = FAMILY) =>
    setDoc(doc(db, 'robots', id), { familyId, name: 'Kitchen', addedBy: by, addedAt: serverTimestamp() });

  it('adults register robots; children and outsiders cannot', async () => {
    await seedFamily();
    await assertSucceeds(robot(as('owner')));
    await assertSucceeds(robot(as('dad'), 'sohail-0000ff', 'dad'));
    await assertFails(robot(as('kid'), 'sohail-111111', 'kid'));
    await assertFails(robot(as('stranger'), 'sohail-222222', 'stranger'));
  });

  it('device ids must look like sohail-xxxxxx', async () => {
    await seedFamily();
    await assertFails(robot(as('owner'), 'sohail-A1B2C3'));
    await assertFails(robot(as('owner'), 'robot-123456'));
    await assertFails(robot(as('owner'), 'sohail-a1b2c3d'));
  });

  it('a registered robot cannot be taken by another family', async () => {
    await seedFamily();
    await robot(as('owner'));
    await createFamily(as('other'), 'other', 'OtherFamily12345', 'Others');
    await assertFails(robot(as('other'), 'sohail-a1b2c3', 'other', 'OtherFamily12345'));
    await assertFails(updateDoc(doc(as('other'), 'robots', 'sohail-a1b2c3'), { familyId: 'OtherFamily12345' }));
    await assertFails(getDoc(doc(as('other'), 'robots', 'sohail-a1b2c3')));
  });

  it('family members list robots; adults rename and remove them', async () => {
    await seedFamily();
    await robot(as('owner'));
    await assertSucceeds(getDocs(query(collection(as('kid'), 'robots'), where('familyId', '==', FAMILY))));
    await assertFails(getDocs(query(collection(as('stranger'), 'robots'), where('familyId', '==', FAMILY))));
    await assertFails(updateDoc(doc(as('kid'), 'robots', 'sohail-a1b2c3'), { name: 'Mine' }));
    await assertFails(updateDoc(doc(as('dad'), 'robots', 'sohail-a1b2c3'), { familyId: 'Elsewhere123456' }));
    await assertSucceeds(updateDoc(doc(as('dad'), 'robots', 'sohail-a1b2c3'), { name: 'Living room' }));
    await assertFails(deleteDoc(doc(as('kid'), 'robots', 'sohail-a1b2c3')));
    await assertSucceeds(deleteDoc(doc(as('dad'), 'robots', 'sohail-a1b2c3')));
  });
});
