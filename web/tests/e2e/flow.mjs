// End-to-end test: real browser, real website build, Firebase emulators.
// Run with: npm run build && npm run test:e2e
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const BASE = 'http://127.0.0.1:4173';
const shots = process.env.E2E_SCREENSHOTS || 'test-results/e2e';
mkdirSync(shots, { recursive: true });

const preview = spawn('npx', ['vite', 'preview', '--strictPort'], { stdio: 'ignore' });
const cleanup = () => preview.kill();
process.on('exit', cleanup);

async function waitForServer() {
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(BASE)).ok) return; } catch { /* not yet */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('vite preview did not start');
}

let failures = 0;
function check(cond, what) {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${what}`);
  if (!cond) failures++;
}

const stamp = Date.now();
const users = {
  aisha: { name: 'Aisha', email: `aisha.${stamp}@example.com`, password: 'correct-horse-1' },
  rashid: { name: 'Rashid', email: `rashid.${stamp}@example.com`, password: 'battery-staple-2' },
  zed: { name: 'Zed', email: `zed.${stamp}@example.com`, password: 'not-my-robot-3' },
};

async function newUser(browser, { width = 1100, height = 900 } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height } });
  const page = await ctx.newPage();
  page.errors = [];
  page.on('pageerror', (e) => page.errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') page.errors.push(m.text()); });
  return page;
}

async function signUp(page, u) {
  await page.click('#tab-up');
  await page.waitForSelector('#name', { state: 'visible' });
  await page.fill('#name', u.name);
  await page.fill('#email', u.email);
  await page.fill('#password', u.password);
  await page.click('#auth-submit');
}

await waitForServer();
const browser = await chromium.launch();
try {
  // ---- Aisha creates an account and a family ----
  const a = await newUser(browser);
  await a.goto(BASE);
  // Safety: this test creates and deletes accounts. Never let it touch a real project.
  if (!(await a.isVisible('.emu'))) {
    throw new Error('Refusing to run: the site is not in emulator mode (build with npm run build:test).');
  }
  check(!(await a.isVisible('#name')), 'the name field is hidden on the Sign in tab');
  await a.screenshot({ path: `${shots}/01-sign-in.png` });
  await signUp(a, users.aisha);
  await a.waitForSelector('h1:text-is("Hello, Aisha")');
  check(await a.isVisible('text=Check your inbox to verify'), 'new email accounts are asked to verify');
  await a.fill('#family-name', 'The Khans');
  await a.click('#create-btn');
  await a.waitForSelector('#group-id');
  const groupId = (await a.textContent('#group-id')).trim();
  check(/^[A-Za-z0-9]{20}$/.test(groupId), `family group id is a valid MQTT id (${groupId})`);

  await a.fill('#srv-host', '192.168.1.25');
  await a.click('#srv-save');
  await a.waitForSelector('text=192.168.1.25:1883');
  check(true, 'owner saved the message server');

  await a.fill('#srv-host', 'mqtt://bad/host');
  await a.click('#srv-save');
  check((await a.textContent('#srv-error')).includes('without mqtt://'), 'bad server addresses are explained');

  await a.selectOption('#invite-role', 'adult');
  await a.click('#invite-btn');
  await a.waitForSelector('.invite');
  const code = await a.getAttribute('.invite', 'data-code');
  check(/^[A-HJ-NP-Z2-9]{10}$/.test(code), `invite code has the right format (${code})`);

  await a.fill('#robot-id', 'not-a-robot');
  await a.click('#robot-btn');
  check((await a.textContent('#robot-error')).includes('look like sohail-'), 'bad robot ids are explained');
  await a.fill('#robot-id', 'sohail-a1b2c3');
  await a.fill('#robot-name', 'Kitchen');
  await a.click('#robot-btn');
  await a.waitForSelector('.robot >> text=Kitchen');
  check(true, 'owner registered a robot');
  await a.screenshot({ path: `${shots}/02-family-owner.png`, fullPage: true });

  // ---- Rashid opens the invite link before having an account ----
  const r = await newUser(browser);
  await r.goto(`${BASE}/join/${code}`);
  await r.waitForSelector('text=Sign in or create an account to join');
  await signUp(r, users.rashid);
  await r.waitForSelector('text=Join The Khans');
  check(await r.isVisible('text=an adult'), 'invite shows the role');
  await r.screenshot({ path: `${shots}/03-join.png` });
  await r.click('#accept');
  await r.waitForSelector('#group-id');
  check((await r.textContent('#group-id')).trim() === groupId, 'new member sees the same family group');
  check(await r.isVisible('text=192.168.1.25:1883'), 'new member sees the server settings');
  check(await r.isVisible('.robot >> text=Kitchen'), 'new member sees the robot');
  check(await r.isVisible('#robot-form'), 'adults can add robots');

  // Opening the same link again goes straight to the family.
  await r.goto(`${BASE}/join/${code}`);
  await r.waitForSelector('#group-id');
  check(true, 'existing members skip the join page');

  // ---- Aisha makes Rashid a child ----
  await a.reload();
  await a.waitForSelector('[data-uid] >> text=Rashid');
  const rashidRow = a.locator('li[data-uid]', { hasText: 'Rashid' });
  await rashidRow.locator('select.role').selectOption('child');
  await a.waitForTimeout(800);
  await r.reload();
  await r.waitForSelector('#group-id');
  check(!(await r.isVisible('#robot-form')), 'children cannot add robots');
  check(!(await r.isVisible('#invite-form')), 'children cannot invite');
  check(await r.isVisible('text=Child'), 'child role is shown');
  await r.screenshot({ path: `${shots}/04-family-child.png`, fullPage: true });

  // ---- Zed cannot take the robot ----
  const z = await newUser(browser, { width: 390, height: 844 });
  await z.goto(BASE);
  await signUp(z, users.zed);
  await z.waitForSelector('h1:text-is("Hello, Zed")');
  await z.fill('#family-name', 'Zed house');
  await z.click('#create-btn');
  await z.waitForSelector('#robot-form');
  await z.fill('#robot-id', 'sohail-a1b2c3');
  await z.click('#robot-btn');
  await z.waitForSelector('#robot-error:not(:empty)');
  check((await z.textContent('#robot-error')).includes('registered to another family'), 'a robot cannot be registered twice');
  const overflow = await z.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  check(!overflow, 'no sideways scrolling on a phone-sized screen');
  await z.screenshot({ path: `${shots}/05-phone.png`, fullPage: true });

  // A used-up or made-up invite code.
  await z.goto(`${BASE}/join/ZZZZZZZZZZ`);
  await z.waitForSelector('text=Invite not valid');
  check(true, 'unknown invite codes are explained');

  // ---- sign out, wrong password, sign back in ----
  await a.click('#sign-out');
  await a.waitForSelector('#auth-form');
  await a.fill('#email', users.aisha.email);
  await a.fill('#password', 'wrong-password');
  await a.click('#auth-submit');
  await a.waitForSelector('#auth-error:not(:empty)');
  check((await a.textContent('#auth-error')).includes('Email or password is wrong'), 'wrong password is explained');
  await a.fill('#password', users.aisha.password);
  await a.click('#auth-submit');
  await a.waitForSelector('h1:text-is("Hello, Aisha")');
  check(await a.isVisible('.row-link >> text=The Khans'), 'families are listed after signing back in');
  await a.screenshot({ path: `${shots}/06-dashboard.png` });

  // ---- Aisha deletes the family ----
  await a.click('.row-link >> text=The Khans');
  await a.waitForSelector('#delete-form');
  await a.fill('#delete-confirm', 'The Khans');
  await a.click('#delete-btn');
  await a.waitForSelector('text=You are not in a family yet');
  check(true, 'owner deleted the family');
  await r.reload();
  await r.waitForSelector('text=Family not found');
  check(true, 'former members lose access');

  for (const [who, p] of [['aisha', a], ['rashid', r], ['zed', z]]) {
    const real = p.errors.filter((e) => !/Failed to load resource|ERR_|favicon|fonts\.g/.test(e) && !/permission/i.test(e));
    check(real.length === 0, `no script errors for ${who}${real.length ? ': ' + real.join(' | ') : ''}`);
  }
} catch (e) {
  console.error(e);
  failures++;
} finally {
  await browser.close();
  cleanup();
}
console.log(failures ? `\n${failures} check(s) failed` : '\nAll end-to-end checks passed');
process.exit(failures ? 1 : 0);
