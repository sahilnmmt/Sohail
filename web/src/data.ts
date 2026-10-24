// All reads and writes. web/firestore.rules is the source of truth for what
// each call is allowed to do; these functions just shape the documents.
import {
  collection,
  collectionGroup,
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
  deleteDoc,
} from 'firebase/firestore';
import type { User } from 'firebase/auth';
import { db } from './firebase';

export type Role = 'owner' | 'adult' | 'child';

export interface Server {
  host: string;
  port: number;
  tls: boolean;
}

export interface Family {
  id: string;
  name: string;
  ownerUid: string;
  server?: Server;
}

export interface Member {
  uid: string;
  role: Role;
  displayName: string;
}

export interface Invite {
  code: string;
  familyId: string;
  familyName: string;
  role: Exclude<Role, 'owner'>;
  expiresAt: Date;
}

export interface Robot {
  id: string;
  name: string;
  familyId: string;
}

export const INVITE_DAYS = 7;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I, O, 0, 1

export function newInviteCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');
}

export function normaliseCode(input: string): string {
  return input.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export const isDeviceId = (s: string) => /^sohail-[0-9a-f]{6}$/.test(s);

export function nameOf(user: User): string {
  return (user.displayName || user.email?.split('@')[0] || 'Me').slice(0, 40);
}

// ---- profile ----------------------------------------------------------------

export async function saveProfile(user: User, displayName: string) {
  await setDoc(doc(db, 'users', user.uid), {
    displayName: displayName.slice(0, 40),
    email: user.email ?? '',
    createdAt: serverTimestamp(),
  });
}

// ---- families -----------------------------------------------------------------

export async function myFamilies(uid: string): Promise<(Family & { role: Role })[]> {
  const memberships = await getDocs(query(collectionGroup(db, 'members'), where('uid', '==', uid)));
  const families = await Promise.all(
    memberships.docs.map(async (m) => {
      const familyRef = m.ref.parent.parent!;
      const f = await getDoc(familyRef);
      return f.exists() ? { id: f.id, ...(f.data() as Omit<Family, 'id'>), role: m.data().role as Role } : null;
    }),
  );
  return families.filter((f): f is Family & { role: Role } => f !== null).sort((a, b) => a.name.localeCompare(b.name));
}

export async function createFamily(user: User, name: string): Promise<string> {
  const ref = doc(collection(db, 'families')); // 20-char id, also the robots' MQTT group id
  const batch = writeBatch(db);
  batch.set(ref, { name, ownerUid: user.uid, createdAt: serverTimestamp() });
  batch.set(doc(db, 'families', ref.id, 'members', user.uid), {
    uid: user.uid, role: 'owner', displayName: nameOf(user), joinedAt: serverTimestamp(),
  });
  await batch.commit();
  return ref.id;
}

export async function getFamily(id: string): Promise<Family | null> {
  const f = await getDoc(doc(db, 'families', id));
  return f.exists() ? { id: f.id, ...(f.data() as Omit<Family, 'id'>) } : null;
}

export const renameFamily = (id: string, name: string) => updateDoc(doc(db, 'families', id), { name });
export const saveServer = (id: string, server: Server) => updateDoc(doc(db, 'families', id), { server });

export async function members(familyId: string): Promise<Member[]> {
  const snap = await getDocs(collection(db, 'families', familyId, 'members'));
  const order: Record<Role, number> = { owner: 0, adult: 1, child: 2 };
  return snap.docs
    .map((d) => d.data() as Member)
    .sort((a, b) => order[a.role] - order[b.role] || a.displayName.localeCompare(b.displayName));
}

export const setRole = (familyId: string, uid: string, role: Exclude<Role, 'owner'>) =>
  updateDoc(doc(db, 'families', familyId, 'members', uid), { role });

export const removeMember = (familyId: string, uid: string) =>
  deleteDoc(doc(db, 'families', familyId, 'members', uid));

export async function deleteFamily(familyId: string, ownerUid: string) {
  const [people, invites, robots] = await Promise.all([
    members(familyId),
    listInvites(familyId),
    listRobots(familyId),
  ]);
  const batch = writeBatch(db);
  for (const m of people) if (m.uid !== ownerUid) batch.delete(doc(db, 'families', familyId, 'members', m.uid));
  for (const i of invites) batch.delete(doc(db, 'invites', i.code));
  for (const r of robots) batch.delete(doc(db, 'robots', r.id));
  batch.delete(doc(db, 'families', familyId));
  batch.delete(doc(db, 'families', familyId, 'members', ownerUid));
  await batch.commit();
}

// ---- invites ------------------------------------------------------------------

export async function createInvite(family: Family, role: Invite['role'], uid: string): Promise<string> {
  const code = newInviteCode();
  await setDoc(doc(db, 'invites', code), {
    familyId: family.id,
    familyName: family.name,
    role,
    createdBy: uid,
    createdAt: serverTimestamp(),
    // A minute short of the limit so client clock skew never trips the rule.
    expiresAt: Timestamp.fromMillis(Date.now() + INVITE_DAYS * 86_400_000 - 60_000),
  });
  return code;
}

function toInvite(code: string, d: Record<string, unknown>): Invite {
  return {
    code,
    familyId: d.familyId as string,
    familyName: d.familyName as string,
    role: d.role as Invite['role'],
    expiresAt: (d.expiresAt as Timestamp).toDate(),
  };
}

export async function listInvites(familyId: string): Promise<Invite[]> {
  const snap = await getDocs(query(collection(db, 'invites'), where('familyId', '==', familyId)));
  return snap.docs
    .map((d) => toInvite(d.id, d.data()))
    .filter((i) => i.expiresAt > new Date())
    .sort((a, b) => a.expiresAt.getTime() - b.expiresAt.getTime());
}

export async function getInvite(code: string): Promise<Invite | null> {
  const d = await getDoc(doc(db, 'invites', code));
  return d.exists() ? toInvite(d.id, d.data()) : null;
}

export const revokeInvite = (code: string) => deleteDoc(doc(db, 'invites', code));

export async function joinFamily(invite: Invite, user: User) {
  await setDoc(doc(db, 'families', invite.familyId, 'members', user.uid), {
    uid: user.uid,
    role: invite.role,
    displayName: nameOf(user),
    joinedAt: serverTimestamp(),
    invite: invite.code,
  });
}

export async function isMemberOf(familyId: string, uid: string): Promise<boolean> {
  try {
    return (await getDoc(doc(db, 'families', familyId, 'members', uid))).exists();
  } catch {
    return false; // not readable: not a member
  }
}

// ---- robots -------------------------------------------------------------------

export async function listRobots(familyId: string): Promise<Robot[]> {
  const snap = await getDocs(query(collection(db, 'robots'), where('familyId', '==', familyId)));
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<Robot, 'id'>) })).sort((a, b) => a.name.localeCompare(b.name));
}

export async function addRobot(familyId: string, deviceId: string, name: string, uid: string) {
  await setDoc(doc(db, 'robots', deviceId), { familyId, name, addedBy: uid, addedAt: serverTimestamp() });
}

export const renameRobot = (id: string, name: string) => updateDoc(doc(db, 'robots', id), { name });
export const removeRobot = (id: string) => deleteDoc(doc(db, 'robots', id));
