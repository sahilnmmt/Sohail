import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { extractListing, ExtractError } from '../src/server/extract.ts';

const fixture = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8');

test('reads schema.org JSON-LD (Flipkart style)', () => {
  const l = extractListing(fixture('flipkart-jsonld.html'), 'https://www.flipkart.com/samsung-galaxy-s24/p/itm123');
  assert.equal(l.site, 'flipkart.com');
  assert.equal(l.siteName, 'Flipkart');
  assert.equal(l.title, 'SAMSUNG Galaxy S24 5G (Onyx Black, 256 GB)');
  assert.equal(l.price, 62999);
  assert.equal(l.mrp, 89999);
  assert.equal(l.shipping, 0);
  assert.equal(l.currency, 'INR');
  assert.equal(l.brand, 'SAMSUNG');
  assert.equal(l.inStock, true);
  assert.deepEqual(l.seller, { name: 'SuperComNet' });
  assert.equal(l.rating, 4.4);
  assert.equal(l.reviewCount, 21540);
  assert.equal(l.image, 'https://rukminim2.flixcart.com/image/s24.jpeg');
});

test('reads an Amazon product page', () => {
  const l = extractListing(fixture('amazon.html'), 'https://www.amazon.in/dp/B0CS5XW6TN');
  assert.equal(l.siteName, 'Amazon');
  assert.equal(l.title, 'Samsung Galaxy S24 5G AI Smartphone (Onyx Black, 8GB, 256GB Storage)');
  assert.equal(l.price, 64999);
  assert.equal(l.mrp, 89999);
  assert.equal(l.currency, 'INR');
  assert.equal(l.rating, 4.3);
  assert.equal(l.reviewCount, 8421);
  assert.equal(l.brand, 'Samsung');
  assert.deepEqual(l.seller, { name: 'Appario Retail Private Ltd', fulfilledBySite: true });
  assert.equal(l.inStock, true);
  assert.equal(l.image, 'https://m.media-amazon.com/images/I/s24.jpg');
});

test('falls back to Open Graph price tags and microdata ratings', () => {
  const l = extractListing(fixture('croma-meta.html'), 'https://www.croma.com/samsung-galaxy-s24/p/303838');
  assert.equal(l.siteName, 'Croma');
  assert.equal(l.title, 'SAMSUNG Galaxy S24 5G (8GB RAM, 256GB, Onyx Black)');
  assert.equal(l.price, 66490);
  assert.equal(l.rating, 4.5); // 9 out of 10
  assert.equal(l.reviewCount, 312);
});

test('reads JSON-LD inside @graph, with string prices and an mpn', () => {
  const l = extractListing(fixture('other-product.html'), 'https://shop.example.in/s24-ultra');
  assert.equal(l.price, 129999);
  assert.equal(l.model, 'SM-S928B');
  assert.equal(l.siteName, 'Example');
});

test('explains captcha pages and pages without a product', () => {
  assert.throws(() => extractListing(fixture('captcha.html'), 'https://www.amazon.in/dp/X'), (e: Error) => {
    assert.ok(e instanceof ExtractError);
    assert.match(e.message, /Amazon blocked automatic reading/);
    return true;
  });
  assert.throws(
    () => extractListing('<html><head><title>Hello</title></head></html>', 'https://example.com/'),
    /Couldn't find a price on this Example page/,
  );
});
