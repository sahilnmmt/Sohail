// Virtual robot end-to-end: the robot page in a real browser (WebSocket) and
// an "app" client over plain TCP, as the Android app connects, on one broker.
//   MQTT_TCP=mqtt://127.0.0.1:1883 MQTT_WS=ws://127.0.0.1:8080 node tests/e2e/robot.mjs
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import mqtt from 'mqtt';
import { chromium } from 'playwright';

const BASE = 'http://127.0.0.1:4173';
const TCP = process.env.MQTT_TCP ?? 'mqtt://127.0.0.1:1883';
const WS = process.env.MQTT_WS ?? 'ws://127.0.0.1:8080';
const GROUP = `testfam${Date.now() % 100000}`;
const shots = process.env.E2E_SCREENSHOTS || 'test-results/e2e';
mkdirSync(shots, { recursive: true });

const preview = spawn('npx', ['vite', 'preview', '--strictPort'], { stdio: 'ignore' });
process.on('exit', () => preview.kill());
for (let i = 0; i < 60; i++) {
  try { if ((await fetch(BASE)).ok) break; } catch { /* starting */ }
  await new Promise((r) => setTimeout(r, 500));
}

let failures = 0;
const check = (cond, what) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${what}`); if (!cond) failures++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- the "app" ----
const app = mqtt.connect(TCP, { clientId: 'app-e2e001', clean: true });
const seen = [];
const status = {};
app.on('message', (topic, payload) => {
  const s = payload.toString();
  if (topic.endsWith('/status')) status[topic.split('/')[3]] = s;
  else seen.push(JSON.parse(s));
});
await new Promise((res, rej) => { app.once('connect', res); app.once('error', rej); });
await app.subscribeAsync([`sohail/v1/group/${GROUP}/inbox`, 'sohail/v1/dev/+/status'], { qos: 1 });
const send = (msg) => app.publishAsync(`sohail/v1/group/${GROUP}/inbox`, JSON.stringify({
  v: 1, id: Math.random().toString(16).slice(2, 18), from: 'app-e2e001', name: 'Sahil', ts: Math.floor(Date.now() / 1000), ...msg,
}), { qos: 1 });
async function until(cond, ms = 5000) { for (let t = 0; t < ms && !cond(); t += 100) await sleep(100); return cond(); }

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1100, height: 950 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`${BASE}/robot?group=${GROUP}&broker=${encodeURIComponent(WS)}&autoconnect=1`);
  await page.waitForSelector('#netlabel:text("connected")', { timeout: 15000 });
  const id = (await page.textContent('#device-id')).trim();
  check(/^sohail-[0-9a-f]{6}$/.test(id), `robot has a real-looking id (${id})`);
  check(await until(() => status[id] === 'online'), 'the app sees the robot come online');
  check(await until(async () => (await page.textContent('#state')) === 'idle'), 'robot is idle after connecting');

  // App -> robot
  await send({ type: 'nudge' });
  await page.waitForSelector('#state:text("notify")');
  check(true, 'a nudge from the app makes the robot show "new message"');
  await page.click('#touchpad');
  await page.waitForSelector('#state:text("showing")');
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${shots}/robot-1-nudge.png` });
  check(true, 'tapping the head shows the nudge');
  await page.waitForSelector('#state:text("idle")', { timeout: 10000 });

  await send({ type: 'text', text: 'Dinner is ready! Come down please' });
  await page.waitForSelector('#state:text("notify")');
  await page.click('#g-press');
  await page.waitForTimeout(700);
  await page.screenshot({ path: `${shots}/robot-2-text.png` });
  check((await page.textContent('#log')).includes('Dinner is ready'), 'a text from the app reaches the robot');
  await page.waitForSelector('#state:text("idle")', { timeout: 15000 });

  // Robot -> app (real button through the gesture decoder)
  const box = await page.locator('#boot').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down(); await sleep(120); await page.mouse.up();
  check(await until(() => seen.some((m) => m.from === id && m.type === 'nudge')), 'pressing the robot button sends a nudge the app receives');
  const nudge = seen.find((m) => m.from === id);
  check(nudge?.v === 1 && /^[0-9a-f]{16}$/.test(nudge.id) && nudge.name === 'Virtual robot' && nudge.ts > 1.7e9,
    'the nudge has the firmware message format');

  await page.waitForTimeout(2500); // let the "Nudge sent!" reaction finish
  await page.click('#g-double'); // open picker (happy)
  await page.click('#g-press');  // -> love
  await page.click('#g-double'); // send
  check(await until(() => seen.some((m) => m.from === id && m.type === 'emoji' && m.emoji === 'love')), 'the emoji picker sends "love" to the app');

  // Invalid traffic is ignored by the firmware decoder
  await app.publishAsync(`sohail/v1/group/${GROUP}/inbox`, '{"v":1,"type":"nudge"}', { qos: 1 });
  check(await until(async () => (await page.textContent('#log')).includes('ignored invalid message')), 'invalid messages are rejected by the firmware decoder');
  check(!seen.some((m) => m.from === id && m.type === 'text'), 'the robot never echoes texts');

  await page.screenshot({ path: `${shots}/robot-3-overview.png`, fullPage: true });
  check(errors.length === 0, `no page errors${errors.length ? ': ' + errors.join(' | ') : ''}`);

  await page.close();
  check(await until(() => status[id] === 'offline'), 'the app sees the robot go offline when the page closes');
} catch (e) {
  console.error(e);
  failures++;
} finally {
  await browser.close();
  app.end(true);
}
console.log(failures ? `\n${failures} check(s) failed` : '\nAll virtual robot checks passed');
process.exit(failures ? 1 : 0);
