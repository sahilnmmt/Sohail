// Virtual robot: the firmware's robot logic (WebAssembly build of
// firmware/sim) wired to a real MQTT connection, like firmware/main does on
// the ESP32: same topics, presence, message decoder and encoder.
import './style.css';
import './robot.css';
import mqtt, { type MqttClient } from 'mqtt';
import { onAuthStateChanged, type User } from 'firebase/auth';
import wasmUrl from '../../firmware/sim/web/sohail.wasm?url';
import { auth } from './firebase';
import * as data from './data';
import { $, describeError, esc } from './html';

// robot_event_type_t and action flags from firmware/components/sohail_core/include/sohail/robot.h
const EV = { TICK: 0, WIFI_UP: 3, WIFI_DOWN: 4, CLOUD_UP: 5, CLOUD_DOWN: 6, BTN_SHORT: 8, BTN_DOUBLE: 9, TOUCH: 13 };
const EV_NAME: Record<number, string> = { 8: 'press', 9: 'double-press', 10: 'hold', 11: 'hold released', 12: 'long hold' };
const ACT = { SEND: 1, CHIME: 2, RESET: 4 };
const CHIMES = ['message', 'sent', 'error', 'happy', 'boot'];
const W = 240, H = 280;

interface Wasm {
  memory: WebAssembly.Memory;
  _initialize(): void;
  init(seed: number, now: number): void;
  post(ev: number, now: number): number;
  tick(now: number): number;
  button(pressed: number, now: number): number;
  render(now: number): void;
  framebuffer(): number;
  state_name(): number;
  unread(): number;
  last_chime(): number;
  last_send_type(): number;
  last_send_emoji(): number;
  emoji_name(e: number): number;
  chime(id: number, volume: number): number;
  audio_buf(): number;
  name_buf(): number;
  id_buf(): number;
  json_buf(): number;
  json_buf_len(): number;
  set_identity(): number;
  receive_json(len: number, now: number): number;
  encode_last_send(unixTs: number): number;
}

let w: Wasm;
let client: MqttClient | null = null;
let lastStep = 0, lastRender = 0, pressed = false, pressStart = 0, lastState = '';
let audio: AudioContext | null = null;
let user: User | null = null;
let families: (data.Family & { role: data.Role })[] = [];

const ctx = $<HTMLCanvasElement>('#screen').getContext('2d')!;
const img = ctx.createImageData(W, H);
const enc = new TextEncoder();
const dec = new TextDecoder();

// ---- settings (remembered in this browser only) ----
const store = {
  get(k: string) { try { return localStorage.getItem(`sohail.robot.${k}`); } catch { return null; } },
  set(k: string, v: string) { try { localStorage.setItem(`sohail.robot.${k}`, v); } catch { /* private mode */ } },
};
function randomHex(n: number) {
  return Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, '0')).join('').slice(0, n);
}
let deviceId = store.get('id') ?? '';
if (!data.isDeviceId(deviceId)) {
  deviceId = `sohail-${randomHex(6)}`;
  store.set('id', deviceId);
}
const params = new URLSearchParams(location.search);

// ---- wasm helpers ----
const mem = () => new Uint8Array(w.memory.buffer);
function cstr(p: number) { const m = mem(); let e = p; while (m[e]) e++; return dec.decode(m.subarray(p, e)); }
function putStr(p: number, s: string, max: number) {
  let b = enc.encode(s);
  if (b.length > max) b = b.subarray(0, max);
  const m = mem(); m.set(b, p); m[p + b.length] = 0;
}
const now = () => Math.floor(performance.now()) >>> 0;

function log(text: string, kind = '') {
  const li = document.createElement('li');
  const t = new Date();
  li.innerHTML = `<time>${t.toTimeString().slice(0, 8)}</time><span class="${kind ? 'k-' + kind : ''}">${esc(text)}</span>`;
  const list = $('#log');
  list.prepend(li);
  while (list.children.length > 100) list.lastChild!.remove();
}

function playChime(id: number) {
  if (!$<HTMLInputElement>('#sound').checked || id < 0) return;
  try {
    audio ??= new AudioContext();
    const n = w.chime(id, 60);
    const pcm = new Int16Array(w.memory.buffer, w.audio_buf(), n);
    const buf = audio.createBuffer(1, n, 16000);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < n; i++) ch[i] = pcm[i] / 32768;
    const src = audio.createBufferSource();
    src.buffer = buf; src.connect(audio.destination); src.start();
  } catch { /* sound is optional */ }
}

// ---- MQTT, mirroring firmware/main/messaging.c ----
const topics = (group: string) => ({
  inbox: `sohail/v1/dev/${deviceId}/inbox`,
  status: `sohail/v1/dev/${deviceId}/status`,
  group: `sohail/v1/group/${group}/inbox`,
});

function publishSend(group: string) {
  const id = randomHex(16);
  putStr(w.id_buf(), id, 24);
  const len = w.encode_last_send(Math.floor(Date.now() / 1000));
  if (len < 0 || !client?.connected) {
    log('could not send (not connected)', 'warn');
    return false;
  }
  const json = dec.decode(mem().subarray(w.json_buf(), w.json_buf() + len));
  client.publish(topics(group).group, json, { qos: 1 });
  const t = w.last_send_type();
  log(t === 0 ? 'sent a nudge to the family' : `sent "${cstr(w.emoji_name(w.last_send_emoji()))}" to the family`, 'send');
  return true;
}

function actions(flags: number) {
  if (flags < 0) return;
  if (flags & ACT.CHIME) {
    const c = w.last_chime();
    playChime(c);
    if (c >= 0) log(`chime: ${CHIMES[c]}`);
  }
  if (flags & ACT.SEND) {
    if (!publishSend(currentGroup)) actions(w.post(14 /* EV_SEND_FAILED */, advance()));
  }
  if (flags & ACT.RESET) {
    log('factory reset (virtual robot: restarts and reconnects)', 'warn');
    boot();
  }
}

function advance() {
  const t = now();
  if (t - lastStep > 2000) lastStep = t - 10;
  while (t - lastStep >= 10) {
    lastStep += 10;
    const r = w.button(pressed ? 1 : 0, lastStep);
    if (r >= 0) {
      log(`button: ${EV_NAME[r & 0xff] ?? r & 0xff}`);
      actions(r >> 8);
    }
    if (lastStep % 50 < 10) actions(w.tick(lastStep));
  }
  return lastStep;
}
const post = (ev: number) => actions(w.post(ev, advance()));

let currentGroup = '';

function connect(group: string, name: string, url: string) {
  disconnect();
  currentGroup = group;
  putStr(w.id_buf(), deviceId, 24);
  putStr(w.name_buf(), name, 16);
  if (!w.set_identity()) throw new Error('Robot name is too long.');
  boot();
  const tp = topics(group);
  log(`connecting to ${url} as ${deviceId}`);
  setNet('connecting');
  client = mqtt.connect(url, {
    clientId: deviceId,
    keepalive: 30,
    clean: true,
    reconnectPeriod: 3000,
    connectTimeout: 10_000,
    will: { topic: tp.status, payload: 'offline', qos: 1, retain: true },
  });
  client.on('connect', () => {
    client!.subscribe([tp.inbox, tp.group], { qos: 1 });
    client!.publish(tp.status, 'online', { qos: 1, retain: true });
    log(`connected; listening on group "${group}"`);
    setNet('online');
    post(EV.CLOUD_UP);
  });
  client.on('close', () => {
    if (netState === 'online') {
      log('connection lost, retrying…', 'warn');
      post(EV.CLOUD_DOWN);
    }
    setNet(client ? 'connecting' : 'offline');
  });
  client.on('error', (e) => {
    log(`server error: ${e.message}`, 'warn');
    $('#conn-error').textContent = `Could not connect: ${e.message}`;
  });
  client.on('message', (topic, payload) => {
    if (payload.length > w.json_buf_len()) {
      log('ignored a message larger than 1 KB', 'warn');
      return;
    }
    mem().set(payload, w.json_buf());
    const flags = w.receive_json(payload.length, advance());
    let who = '';
    try {
      const m = JSON.parse(dec.decode(payload));
      if (m.from === deviceId) return; // our own message coming back from the group
      who = `${m.name || m.from}: ${m.type}${m.emoji ? ' ' + m.emoji : ''}${m.text ? ' "' + m.text + '"' : ''}`;
    } catch { /* logged below */ }
    if (flags < 0) {
      log(`ignored invalid message on ${topic}`, 'warn');
      return;
    }
    log(`received ${who}`, 'recv');
    actions(flags);
  });
}

function disconnect() {
  if (!client) return;
  const c = client;
  client = null;
  if (c.connected) c.publish(topics(currentGroup).status, 'offline', { qos: 1, retain: true });
  c.end(false);
  post(EV.CLOUD_DOWN);
  setNet('offline');
  log('disconnected');
}

let netState: 'offline' | 'connecting' | 'online' = 'offline';
function setNet(s: typeof netState) {
  netState = s;
  $('#netdot').className = 'dot ' + (s === 'online' ? 'ok' : s === 'connecting' ? 'warn' : 'bad');
  $('#netlabel').textContent = s === 'online' ? 'connected' : s === 'connecting' ? 'connecting…' : 'offline';
  $('#connect').textContent = s === 'offline' ? 'Connect robot' : 'Reconnect';
  $('#disconnect').hidden = s === 'offline';
  updateRegister();
}

function boot() {
  lastStep = now();
  w.init((Math.random() * 2 ** 31) | 0, lastStep);
  post(EV.WIFI_UP); // a virtual robot is always "on Wi-Fi"
  if (client?.connected) post(EV.CLOUD_UP);
}

// ---- drawing ----
function frame() {
  const t = advance();
  if (pressed) {
    const held = now() - pressStart;
    $('#holdbar').firstElementChild!.setAttribute('style', `width:${Math.min(100, held / 100)}%`);
    $('#holdbar').classList.toggle('reset', held >= 3000);
  }
  if (t - lastRender >= 40) {
    lastRender = t;
    w.render(t);
    const fb = new Uint16Array(w.memory.buffer, w.framebuffer(), W * H);
    const d = img.data;
    for (let i = 0, j = 0; i < fb.length; i++, j += 4) {
      const c = fb[i];
      d[j] = (c >> 8) & 0xf8; d[j + 1] = (c >> 3) & 0xfc; d[j + 2] = (c << 3) & 0xf8; d[j + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    const st = cstr(w.state_name());
    if (st !== lastState) { lastState = st; $('#state').textContent = st; }
    $('#unread').textContent = String(w.unread());
  }
  requestAnimationFrame(frame);
}

// ---- accounts: optional family picker and robot registration ----
function updateRegister() {
  const fam = families.find((f) => f.id === currentGroup);
  const canRegister = !!user && !!fam && fam.role !== 'child' && netState !== 'offline';
  $('#register').hidden = !canRegister;
  if (fam) $('#register-btn').textContent = `Register ${deviceId} in ${fam.name}`;
}

onAuthStateChanged(auth, async (u) => {
  user = u;
  families = [];
  if (u) {
    try { families = await data.myFamilies(u.uid); } catch { families = []; }
  }
  const pick = $<HTMLSelectElement>('#family');
  $('#family-pick').hidden = families.length === 0;
  pick.innerHTML = '<option value="">Choose…</option>' +
    families.map((f) => `<option value="${esc(f.id)}">${esc(f.name)}</option>`).join('');
  updateRegister();
});

// ---- wiring ----
function wire() {
  const boot_ = $<HTMLButtonElement>('#boot');
  const setPressed = (v: boolean) => {
    pressed = v;
    boot_.classList.toggle('down', v);
    if (v) pressStart = now();
    else { $('#holdbar').firstElementChild!.setAttribute('style', 'width:0'); $('#holdbar').classList.remove('reset'); }
  };
  boot_.addEventListener('pointerdown', (e) => { e.preventDefault(); boot_.setPointerCapture(e.pointerId); setPressed(true); });
  boot_.addEventListener('pointerup', () => setPressed(false));
  boot_.addEventListener('pointercancel', () => setPressed(false));
  boot_.addEventListener('keydown', (e) => { if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) { e.preventDefault(); setPressed(true); } });
  boot_.addEventListener('keyup', (e) => { if (e.key === ' ' || e.key === 'Enter') setPressed(false); });
  boot_.addEventListener('contextmenu', (e) => e.preventDefault());

  const touch = () => { log('head touched'); post(EV.TOUCH); };
  $('#touchpad').addEventListener('click', touch);
  $('#g-touch').addEventListener('click', touch);
  $('#g-press').addEventListener('click', () => { log('button: press'); post(EV.BTN_SHORT); });
  $('#g-double').addEventListener('click', () => { log('button: double-press'); post(EV.BTN_DOUBLE); });

  $('#device-id').textContent = deviceId;
  $('#hw-id').textContent = deviceId;
  $('#copy-id').addEventListener('click', () => navigator.clipboard?.writeText(deviceId).catch(() => undefined));

  const preset = $<HTMLSelectElement>('#broker-preset');
  const groupIn = $<HTMLInputElement>('#group');
  const nameIn = $<HTMLInputElement>('#name');
  const urlIn = $<HTMLInputElement>('#broker-url');
  groupIn.value = params.get('group') ?? store.get('group') ?? '';
  nameIn.value = store.get('name') ?? 'Virtual robot';
  const savedUrl = params.get('broker') ?? store.get('broker') ?? preset.options[0].value;
  if ([...preset.options].some((o) => o.value === savedUrl)) preset.value = savedUrl;
  else { preset.value = 'custom'; urlIn.value = savedUrl; }
  const syncCustom = () => { $('#custom-field').hidden = preset.value !== 'custom'; };
  preset.addEventListener('change', syncCustom);
  syncCustom();

  $<HTMLSelectElement>('#family').addEventListener('change', (e) => {
    const f = families.find((x) => x.id === (e.target as HTMLSelectElement).value);
    if (!f) return;
    groupIn.value = f.id;
    const host = f.server?.host;
    const match = [...preset.options].find((o) => o.dataset.host === host);
    if (match) { preset.value = match.value; syncCustom(); }
    else if (host) log(`family server ${host} has no known WebSocket address; choose one below`, 'warn');
  });

  $('#conn-form').addEventListener('submit', (e) => {
    e.preventDefault();
    $('#conn-error').textContent = '';
    const group = groupIn.value.trim();
    const name = nameIn.value.trim();
    const url = preset.value === 'custom' ? urlIn.value.trim() : preset.value;
    if (!data.isDeviceId(deviceId) || !/^[A-Za-z0-9_-]{1,24}$/.test(group)) {
      $('#conn-error').textContent = 'The family group is 1-24 letters, digits, - or _ (copy it from the family page or the app).';
      return;
    }
    if (!/^wss?:\/\//.test(url)) { $('#conn-error').textContent = 'The server must be a ws:// or wss:// WebSocket URL.'; return; }
    if (location.protocol === 'https:' && url.startsWith('ws://')) {
      $('#conn-error').textContent = 'This page is served over HTTPS, so the server needs a wss:// address.';
      return;
    }
    store.set('group', group); store.set('name', name); store.set('broker', url);
    try { connect(group, name, url); } catch (err) { $('#conn-error').textContent = describeError(err); }
  });
  $('#disconnect').addEventListener('click', disconnect);

  $('#register-btn').addEventListener('click', async () => {
    const fam = families.find((f) => f.id === currentGroup);
    if (!fam || !user) return;
    const btn = $<HTMLButtonElement>('#register-btn');
    $('#register-error').textContent = '';
    btn.disabled = true;
    try {
      const existing = await data.listRobots(fam.id);
      if (existing.some((r) => r.id === deviceId)) { btn.textContent = 'Already registered in this family'; return; }
      await data.addRobot(fam.id, deviceId, nameIn.value.trim() || 'Virtual robot', user.uid);
      btn.textContent = `Registered in ${fam.name}`;
      log(`registered in family "${fam.name}"`);
    } catch (e) {
      $('#register-error').textContent = (e as { code?: string }).code === 'permission-denied'
        ? 'This robot ID is registered to another family.' : describeError(e);
      btn.disabled = false;
    }
  });
  window.addEventListener('beforeunload', () => disconnect());
}

async function start() {
  const bytes = await (await fetch(wasmUrl)).arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {
    wasi_snapshot_preview1: {
      random_get: (ptr: number, len: number) => { crypto.getRandomValues(new Uint8Array(w.memory.buffer, ptr, len)); return 0; },
    },
  });
  w = instance.exports as unknown as Wasm;
  w._initialize();
  wire();
  boot();
  setNet('offline');
  log(`robot ${deviceId} ready; enter the family group and connect`);
  requestAnimationFrame(frame);
  if (params.get('autoconnect') === '1') $<HTMLFormElement>('#conn-form').requestSubmit();
}
start().catch((e) => log(`could not start: ${e}`, 'warn'));
