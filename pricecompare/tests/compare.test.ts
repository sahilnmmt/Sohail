import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareListings } from '../src/shared/compare.ts';
import { groupListings } from '../src/shared/match.ts';
import type { Listing } from '../src/shared/types.ts';
import { sampleListings } from '../src/server/sources/sample.ts';

const listing = (over: Partial<Listing>): Listing => ({
  site: 'shop.in',
  siteName: 'Shop',
  title: 'Apple iPhone 15 (128 GB) - Black',
  url: 'https://shop.in/p',
  price: 100,
  currency: 'INR',
  ...over,
});

test('price differences are measured from the cheapest in-stock total, delivery included', () => {
  const c = compareListings([
    listing({ site: 'a', siteName: 'A', price: 1000, shipping: 0 }),
    listing({ site: 'b', siteName: 'B', price: 950, shipping: 100 }), // 1050 delivered
    listing({ site: 'c', siteName: 'C', price: 900, shipping: 0, inStock: false }),
  ])!;
  assert.deepEqual(c.offers.map((o) => o.siteName), ['A', 'B', 'C']);
  assert.equal(c.summary.lowest, 1000);
  assert.equal(c.offers[1].diff, 50);
  assert.equal(c.offers[1].diffPercent, 5);
  assert.ok(c.offers[0].badges.includes('cheapest'));
  assert.ok(c.offers[2].badges.includes('out-of-stock'));
  assert.ok(!c.offers[2].badges.includes('cheapest'));
  assert.equal(c.summary.spread, 50);
});

test('a high rating from a handful of reviews does not beat a slightly lower one from thousands', () => {
  const c = compareListings([
    listing({ site: 'a', siteName: 'A', rating: 4.9, reviewCount: 4 }),
    listing({ site: 'b', siteName: 'B', rating: 4.5, reviewCount: 5000 }),
  ])!;
  const top = c.offers.find((o) => o.badges.includes('top-rated'))!;
  assert.equal(top.siteName, 'B');
});

test('value score prefers a slightly dearer offer with a far better rating and seller', () => {
  const c = compareListings([
    listing({ site: 'a', siteName: 'A', price: 1000, rating: 2.5, reviewCount: 2000, seller: { name: 'X', rating: 2.5 } }),
    listing({ site: 'b', siteName: 'B', price: 1030, rating: 4.7, reviewCount: 2000, seller: { name: 'Y', fulfilledBySite: true } }),
  ])!;
  assert.equal(c.offers.find((o) => o.badges.includes('best-value'))!.siteName, 'B');
  assert.ok(c.offers.find((o) => o.siteName === 'B')!.badges.includes('trusted-seller'));
});

test('MRP discount is reported', () => {
  const c = compareListings([listing({ price: 750, mrp: 1000 })])!;
  assert.equal(c.offers[0].discountPercent, 25);
});

test('warns about different variants, odd prices, mixed currencies and unknown delivery', () => {
  const c = compareListings([
    listing({ site: 'a', siteName: 'A', price: 60000, shipping: 0, title: 'Apple iPhone 15 (128 GB) - Black' }),
    listing({ site: 'b', siteName: 'B', price: 61000, shipping: 0, title: 'Apple iPhone 15 (256 GB) - Black' }),
    listing({ site: 'c', siteName: 'C', price: 62000, title: 'Apple iPhone 15 (128 GB) - Blue' }),
    listing({ site: 'd', siteName: 'D', price: 20000, shipping: 0, title: 'Apple iPhone 15 (128 GB) - Black' }),
    listing({ site: 'e', siteName: 'E', price: 799, currency: 'USD' }),
  ])!;
  const all = c.warnings.join('\n');
  assert.equal(c.currency, 'INR');
  assert.match(all, /Left out E: priced in USD/);
  assert.match(all, /Different storage\/memory listed: 128GB \(D, A, C\) vs 256GB \(B\)/);
  assert.match(all, /Different colours listed/);
  assert.match(all, /Delivery charge not known for C/);
  assert.match(all, /D is 67% below the typical price/);
});

test('flags a listing that looks like a different product', () => {
  const c = compareListings([
    listing({ site: 'a', siteName: 'A' }),
    listing({ site: 'b', siteName: 'B', title: 'Prestige Svachh Pressure Cooker 5 L' }),
  ])!;
  assert.ok(c.warnings.some((w) => w.includes('B listing may be a different product')));
});

test('sample catalogue groups into its products, one per search phrase', () => {
  const listings = sampleListings();
  const groups = groupListings(listings);
  const products = new Set(listings.map((l) => l.url.split(/[?=]/).pop()));
  assert.equal(groups.length, products.size);
  for (const g of groups) assert.equal(new Set(g.map((l) => l.url.split(/[?=]/).pop())).size, 1, g.map((l) => l.title).join(' | '));
});

test('grouping keeps neighbouring models apart even without a brand', () => {
  const titles = [
    'Apple iPhone 15 (128 GB) - Black',
    'Apple iPhone 15 (Black, 128 GB)',
    'Apple iPhone 15 Pro (128 GB) - Black Titanium',
    'Apple iPhone 14 (128 GB) - Black',
    'Apple iPhone 15 (256 GB) - Black',
  ];
  const groups = groupListings(titles.map((title, i) => listing({ site: `s${i}`, title })));
  assert.deepEqual(groups.map((g) => g.length), [2, 1, 1, 1]);
});
