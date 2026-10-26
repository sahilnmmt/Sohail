// Drives the built app in Chromium: search, sort, and compare offers added by
// hand. Screenshots go to test-results/e2e. Run with `npm run test:e2e`.

import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const PORT = 8799;
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = new URL('../../test-results/e2e/', import.meta.url).pathname;
mkdirSync(SHOTS, { recursive: true });

const server = spawn(process.execPath, ['src/server/main.ts'], {
  env: { ...process.env, PORT: String(PORT) },
  stdio: ['ignore', 'inherit', 'inherit'],
});
const fail = (msg) => {
  throw new Error(msg);
};

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try {
      if ((await fetch(`${BASE}/api/health`)).ok) return;
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  fail('server did not start');
}

let browser;
try {
  browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  await waitForServer();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));

  // Everything shows on first load.
  await page.goto(BASE);
  await page.locator('article.product').first().waitFor();
  console.log('products on first load:', await page.locator('article.product').count());

  // Search.
  await page.fill('#q', 'galaxy s24');
  await page.click('#search-form button');
  await page.waitForFunction(() => document.querySelectorAll('article.product').length === 1);
  const rows = page.locator('article.product tbody tr');
  if ((await rows.count()) !== 4) fail(`expected 4 offers, got ${await rows.count()}`);
  const first = await rows.first().locator('.site').textContent();
  if (first !== 'Flipkart') fail(`cheapest should be Flipkart, got ${first}`);
  if (!(await page.locator('.notice').textContent()).includes('sample prices')) fail('sample notice missing');
  if (!page.url().includes('q=galaxy+s24')) fail(`query not in URL: ${page.url()}`);
  await page.screenshot({ path: `${SHOTS}search.png`, fullPage: true });

  // Sort by rating.
  await page.selectOption('article.product .sort-select', 'rating');
  const topRated = await rows.first().locator('.site').textContent();
  console.log('top rated after sort:', topRated);

  // Suspicious offer warning on the headphones.
  await page.click('.chip:has-text("Sony WH-1000XM5")');
  await page.waitForFunction(() => document.querySelector('article.product h2')?.textContent?.includes('WH-1000XM5'));
  const warning = await page.locator('.warnings').first().textContent();
  if (!/below the typical price/.test(warning)) fail(`expected a price warning, got ${warning}`);

  // Compare links tab, with offers added by hand.
  await page.click('#tab-links');
  await page.click('#manual summary');
  for (const [shop, price, seller] of [['Shop One', '1999', 'Seller A'], ['Shop Two', '2199', 'Seller B']]) {
    await page.fill('#manual [name="siteName"]', shop);
    await page.fill('#manual [name="price"]', price);
    await page.fill('#manual [name="seller"]', seller);
    await page.fill('#manual [name="title"]', 'Test Kettle 1.5 L');
    await page.click('#add-manual');
  }
  if ((await page.locator('#manual-list li').count()) !== 2) fail('manual offers not listed');
  await page.click('#links-form button[type="submit"]');
  await page.locator('#links-results article.product').waitFor();
  const save = await page.locator('#links-results .save').textContent();
  if (!save.includes('200')) fail(`expected ₹200 saving, got ${save}`);
  await page.screenshot({ path: `${SHOTS}links.png`, fullPage: true });

  // Phone layout: no sideways scrolling.
  const phone = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true });
  await phone.goto(`${BASE}/?q=iphone`);
  await phone.locator('article.product').first().waitFor();
  const overflow = await phone.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  if (overflow > 0) fail(`phone layout scrolls sideways by ${overflow}px`);
  await phone.screenshot({ path: `${SHOTS}phone.png`, fullPage: true });

  if (errors.length) fail(`browser errors:\n${errors.join('\n')}`);
  console.log('e2e: ok');
} finally {
  await browser?.close();
  server.kill();
}
