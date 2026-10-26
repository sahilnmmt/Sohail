import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { createApp } from '../src/server/app.ts';
import { FetchError } from '../src/server/fetchPage.ts';
import { sampleSource } from '../src/server/sources/sample.ts';
import type { CompareLinksResponse, SearchResponse } from '../src/shared/types.ts';

const fixture = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8');

// Saved pages stand in for the real shops.
const PAGES: Record<string, string> = {
  'https://www.amazon.in/dp/B0CS5XW6TN': 'amazon.html',
  'https://www.flipkart.com/samsung-galaxy-s24/p/itm123': 'flipkart-jsonld.html',
  'https://www.croma.com/samsung-galaxy-s24/p/303838': 'croma-meta.html',
  'https://www.amazon.in/dp/CAPTCHA': 'captcha.html',
};
let fetches = 0;
async function fakeFetch(url: string) {
  fetches++;
  if (!PAGES[url]) throw new FetchError('The page could not be loaded (HTTP 404).');
  return { url, html: fixture(PAGES[url]) };
}

const staticDir = mkdtempSync(join(tmpdir(), 'pricecompare-'));
writeFileSync(join(staticDir, 'index.html'), '<!doctype html><title>Price Compare</title>');
const app = createApp({ sources: [sampleSource], fetchPage: fakeFetch, staticDir });
let base = '';
before(async () => {
  await new Promise<void>((r) => app.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${(app.address() as AddressInfo).port}`;
});
after(() => app.close());

const post = (body: unknown) =>
  fetch(`${base}/api/compare-links`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('search returns one comparison per product, sample data flagged', async () => {
  const r = (await (await fetch(`${base}/api/search?q=iphone%2015`)).json()) as SearchResponse;
  assert.equal(r.sample, true);
  assert.equal(r.products.length, 2); // 128 GB and 256 GB
  const [p128] = r.products;
  assert.match(p128.title, /128 GB/);
  assert.equal(p128.offers.length, 4);
  assert.equal(p128.offers[0].siteName, 'Flipkart');
  assert.equal(p128.summary.lowest, 59999);
  assert.ok(p128.offers.every((o, i, all) => i === 0 || o.total >= all[i - 1].total));
});

test('search with no match returns no products', async () => {
  const r = (await (await fetch(`${base}/api/search?q=zzzz`)).json()) as SearchResponse;
  assert.deepEqual(r.products, []);
  assert.equal(r.sample, false);
});

test('compare-links reads each shop page and compares them', async () => {
  const res = await post({
    urls: [
      'https://www.amazon.in/dp/B0CS5XW6TN',
      'https://www.flipkart.com/samsung-galaxy-s24/p/itm123',
      'https://www.croma.com/samsung-galaxy-s24/p/303838',
      'https://www.amazon.in/dp/CAPTCHA',
    ],
    manual: [{ siteName: 'Reliance Digital', price: 65999, shipping: 0, seller: { name: 'Reliance Digital' }, title: 'Samsung Galaxy S24 5G 256 GB, 8 GB RAM, Onyx Black' }],
  });
  assert.equal(res.status, 200);
  const r = (await res.json()) as CompareLinksResponse;
  assert.equal(r.errors.length, 1);
  assert.match(r.errors[0].message, /Amazon blocked automatic reading/);
  const c = r.comparison!;
  assert.deepEqual(
    c.offers.map((o) => [o.siteName, o.total, o.diff]),
    [['Flipkart', 62999, 0], ['Amazon', 64999, 2000], ['Reliance Digital', 65999, 3000], ['Croma', 66490, 3491]],
  );
  assert.equal(c.summary.spread, 3491);
  assert.ok(c.offers[0].badges.includes('cheapest'));
  assert.equal(c.offers[1].seller?.name, 'Appario Retail Private Ltd');
});

test('compare-links caches pages it has read', async () => {
  const before = fetches;
  await post({ urls: ['https://www.flipkart.com/samsung-galaxy-s24/p/itm123'] });
  await post({ urls: ['https://www.flipkart.com/samsung-galaxy-s24/p/itm123'] });
  assert.ok(fetches - before <= 1);
});

test('compare-links validates its input', async () => {
  const cases: [unknown, RegExp][] = [
    [{}, /at least one product link/],
    [{ urls: 'x' }, /must be a list of links/],
    [{ urls: Array.from({ length: 11 }, (_, i) => `https://a.com/${i}`) }, /at most 10 links/],
    [{ manual: [{ siteName: 'X' }] }, /needs a price/],
    [{ manual: [{ price: 5 }] }, /needs a site name/],
    [{ manual: [{ siteName: 'X', price: 5, currency: 'rupees' }] }, /3-letter code/],
  ];
  for (const [body, message] of cases) {
    const res = await post(body);
    assert.equal(res.status, 400, JSON.stringify(body));
    assert.match(((await res.json()) as { error: string }).error, message);
  }
  const res = await fetch(`${base}/api/compare-links`, { method: 'POST', body: '{nope' });
  assert.equal(res.status, 400);
  assert.equal((await fetch(`${base}/api/compare-links`)).status, 405);
});

test('manual offers keep only safe links', async () => {
  const r = (await (await post({ manual: [{ siteName: 'X', price: 5, url: 'javascript:alert(1)' }] })).json()) as CompareLinksResponse;
  assert.equal(r.comparison!.offers[0].url, '');
});

test('serves the web app and refuses paths outside it', async () => {
  const home = await fetch(`${base}/`);
  assert.equal(home.status, 200);
  assert.match(await home.text(), /Price Compare/);
  assert.match(await (await fetch(`${base}/some/route`)).text(), /Price Compare/);
  const traversal = await fetch(`${base}/..%2f..%2fetc%2fpasswd`);
  assert.notEqual(await traversal.text(), readFileSync('/etc/passwd', 'utf8'));
  assert.equal((await fetch(`${base}/%E0%A4%A`)).status, 404);
  assert.equal((await fetch(`${base}/api/nope`)).status, 404);
});
