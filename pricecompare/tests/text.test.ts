import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  detectCurrency, modelCodes, modelConflict, parseCount, parsePrice, parseRating, siteFromUrl,
  titleSimilarity, titleWords, variantConflict, variantOf,
} from '../src/shared/text.ts';

test('parsePrice reads Indian, US and European formats', () => {
  assert.equal(parsePrice('₹1,29,999.00'), 129999);
  assert.equal(parsePrice('Rs. 999'), 999);
  assert.equal(parsePrice('$1,299.99'), 1299.99);
  assert.equal(parsePrice('1.299,99 €'), 1299.99);
  assert.equal(parsePrice('12,50'), 12.5);
  assert.equal(parsePrice('1.299.000'), 1299000);
  assert.equal(parsePrice('66,490'), 66490);
  assert.equal(parsePrice(62999), 62999);
  assert.equal(parsePrice('Currently unavailable'), undefined);
  assert.equal(parsePrice(-5), undefined);
});

test('detectCurrency', () => {
  assert.equal(detectCurrency('₹64,999.00'), 'INR');
  assert.equal(detectCurrency('Rs 499'), 'INR');
  assert.equal(detectCurrency('$10'), 'USD');
  assert.equal(detectCurrency('10 users'), undefined);
});

test('parseRating scales to 5 and rejects nonsense', () => {
  assert.equal(parseRating('4.3 out of 5 stars'), 4.3);
  assert.equal(parseRating('9', 10), 4.5);
  assert.equal(parseRating('4,5'), 4.5);
  assert.equal(parseRating('42'), undefined);
});

test('parseCount', () => {
  assert.equal(parseCount('8,421 ratings'), 8421);
  assert.equal(parseCount('1.2k reviews'), 1200);
  assert.equal(parseCount('2 lakh'), 200000);
});

test('siteFromUrl knows common shops and names others from the domain', () => {
  assert.deepEqual(siteFromUrl('https://www.amazon.in/dp/B0CS5XW6TN'), { site: 'amazon.in', siteName: 'Amazon' });
  assert.deepEqual(siteFromUrl('https://dl.flipkart.com/s/abc'), { site: 'flipkart.com', siteName: 'Flipkart' });
  assert.deepEqual(siteFromUrl('https://shop.example.co/item'), { site: 'shop.example.co', siteName: 'Example' });
  assert.equal(siteFromUrl('not a url').site, 'unknown');
});

test('titleWords joins numbers to units and drops filler', () => {
  assert.deepEqual(titleWords('SAMSUNG Galaxy S24 5G (Onyx Black, 256 GB) (8 GB RAM)'), [
    'samsung', 'galaxy', 's24', '5g', 'onyx', 'black', '256gb', '8gb',
  ]);
  assert.ok(titleWords("Nike Men's Revolution 7").includes('men'));
  assert.ok(titleWords('Samsung 138 cm (55 inches) TV').includes('55inch'));
});

test('variants: storage and size must agree, small size differences are the same item', () => {
  assert.deepEqual(variantOf('Galaxy S24 (8GB, 256GB Storage)').storage, ['256GB', '8GB']);
  assert.equal(variantConflict(variantOf('iPhone 15 (128 GB)'), variantOf('iPhone 15 (256 GB)')), '128GB vs 256GB');
  assert.equal(variantConflict(variantOf('Galaxy S24 8GB 256GB'), variantOf('Galaxy S24 (256 GB) (8 GB RAM)')), undefined);
  assert.equal(variantConflict(variantOf('MacBook Air 13" M3'), variantOf('MacBook Air M3 13.6 inch')), undefined);
  assert.ok(variantConflict(variantOf('Samsung 55 inch TV'), variantOf('Samsung 65 inch TV')));
  assert.equal(variantOf('Apple iPhone 15 (Space Gray)').colour, 'grey');
});

test('modelCodes finds model numbers, not specs', () => {
  assert.deepEqual([...modelCodes('Sony WH-1000XM5 Wireless, 30 Hrs, 5000mAh')], ['WH1000XM5']);
  assert.deepEqual([...modelCodes('Apple MacBook Air MC8K4HN/A M3 256GB')], ['MC8K4HNA']);
});

test('modelConflict separates neighbouring models', () => {
  assert.ok(modelConflict('Apple iPhone 15 (128 GB)', 'Apple iPhone 14 (128 GB)'));
  assert.ok(modelConflict('Apple iPhone 15 (128 GB)', 'Apple iPhone 15 Pro (128 GB)'));
  assert.ok(modelConflict('Samsung Galaxy S24 5G', 'Samsung Galaxy S24 Ultra 5G'));
  assert.ok(modelConflict('Sony WH-1000XM5 Headphones', 'Sony WH-1000XM4 Headphones'));
  assert.equal(modelConflict('Nike Mens Revolution 7 Running Shoe', 'NIKE Revolution 7 Running Shoes For Men'), undefined);
});

test('titleSimilarity: same product on two sites scores high, different products low', () => {
  assert.ok(titleSimilarity('Apple iPhone 15 (128 GB) - Black', 'Apple iPhone 15 (Black, 128 GB)') > 0.9);
  assert.ok(
    titleSimilarity(
      'Samsung Galaxy S24 5G AI Smartphone (Onyx Black, 8GB, 256GB Storage)',
      'SAMSUNG Galaxy S24 5G (Onyx Black, 256 GB) (8 GB RAM)',
    ) > 0.8,
  );
  assert.ok(titleSimilarity('boAt Airdopes 141 TWS Earbuds', 'Sony WH-1000XM5 Headphones') < 0.2);
});
