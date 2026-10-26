import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, test } from 'node:test';
import zlib from 'node:zlib';
import { fetchPage, FetchError, isBlockedAddress } from '../src/server/fetchPage.ts';

const page = readFileSync(new URL('./fixtures/flipkart-jsonld.html', import.meta.url));
let base = '';
const server = http.createServer((req, res) => {
  switch (req.url) {
    case '/page':
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(page);
    case '/gzip':
      res.writeHead(200, { 'Content-Type': 'text/html', 'Content-Encoding': 'gzip' });
      return res.end(zlib.gzipSync(page));
    case '/redirect':
      res.writeHead(302, { Location: '/page' });
      return res.end();
    case '/loop':
      res.writeHead(302, { Location: '/loop' });
      return res.end();
    case '/pdf':
      res.writeHead(200, { 'Content-Type': 'application/pdf' });
      return res.end('%PDF');
    case '/big':
      res.writeHead(200, { 'Content-Type': 'text/html' });
      return res.end('x'.repeat(2000));
    case '/blocked':
      res.writeHead(403);
      return res.end();
    default:
      res.writeHead(404);
      res.end();
  }
});
before(async () => {
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

const local = { allowPrivate: true };

test('downloads a page, following redirects and undoing gzip', async () => {
  const direct = await fetchPage(`${base}/page`, local);
  assert.match(direct.html, /Galaxy S24/);
  const redirected = await fetchPage(`${base}/redirect`, local);
  assert.equal(redirected.url, `${base}/page`);
  assert.match((await fetchPage(`${base}/gzip`, local)).html, /"price":62999/);
});

test('rejects private addresses unless allowed', async () => {
  for (const url of [`${base}/page`, 'http://localhost:1/', 'http://[::1]:1/', 'http://169.254.169.254/latest/meta-data/']) {
    await assert.rejects(fetchPage(url), (e: Error) => e instanceof FetchError && /private or local/.test(e.message), url);
  }
});

test('rejects bad links, non-pages, huge pages, refusals and redirect loops', async () => {
  await assert.rejects(fetchPage('ftp://example.com/x'), /Only http and https/);
  await assert.rejects(fetchPage('https://user:pw@example.com/'), /username or password/);
  await assert.rejects(fetchPage('nonsense'), /not a valid link/);
  await assert.rejects(fetchPage(`${base}/pdf`, local), /not a web page \(application\/pdf\)/);
  await assert.rejects(fetchPage(`${base}/big`, { ...local, maxBytes: 1000 }), /too large/);
  await assert.rejects(fetchPage(`${base}/blocked`, local), /refused the request \(HTTP 403\)/);
  await assert.rejects(fetchPage(`${base}/missing`, local), /HTTP 404/);
  await assert.rejects(fetchPage(`${base}/loop`, local), /Too many redirects/);
});

test('isBlockedAddress', () => {
  for (const a of ['127.0.0.1', '10.1.2.3', '172.20.0.1', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '::1', 'fd00::1', 'fe80::1', '::ffff:127.0.0.1', '224.0.0.1']) {
    assert.equal(isBlockedAddress(a), true, a);
  }
  for (const a of ['8.8.8.8', '104.16.0.1', '2606:4700::1111', '::ffff:8.8.8.8']) {
    assert.equal(isBlockedAddress(a), false, a);
  }
});
