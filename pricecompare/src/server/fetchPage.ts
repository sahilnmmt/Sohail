// Downloads a product page for a link the user pasted.
//
// The server fetches URLs chosen by whoever uses the site, so it refuses
// anything that resolves to a private, loopback or link-local address (checked
// when connecting, so DNS tricks can't get past it), caps the size and time,
// and re-checks every redirect.

import { lookup as dnsLookup, type LookupAddress } from 'node:dns';
import http from 'node:http';
import https from 'node:https';
import { BlockList, isIP, type LookupFunction } from 'node:net';
import zlib from 'node:zlib';

export class FetchError extends Error {}

export interface FetchOptions {
  timeoutMs?: number;
  maxBytes?: number;
  maxRedirects?: number;
  /** Allow private and loopback addresses. Only for tests against a local server. */
  allowPrivate?: boolean;
}

const BLOCKED = new BlockList();
for (const [net, prefix] of [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8], ['169.254.0.0', 16],
  ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['224.0.0.0', 3],
] as const) BLOCKED.addSubnet(net, prefix, 'ipv4');
for (const [net, prefix] of [['::', 127], ['fc00::', 7], ['fe80::', 10], ['ff00::', 8]] as const) {
  BLOCKED.addSubnet(net, prefix, 'ipv6');
}

export function isBlockedAddress(address: string): boolean {
  const mapped = address.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i)?.[1];
  if (mapped) return BLOCKED.check(mapped, 'ipv4');
  const family = isIP(address);
  if (!family) return true;
  return BLOCKED.check(address, family === 4 ? 'ipv4' : 'ipv6');
}

/** DNS lookup that only returns public addresses. */
const safeLookup: LookupFunction = (hostname, options, callback) => {
  dnsLookup(hostname, { ...options, all: true }, (err, addresses: LookupAddress[]) => {
    if (err) return callback(err, '', 0);
    const allowed = addresses.filter((a) => !isBlockedAddress(a.address));
    if (!allowed.length) {
      return callback(new FetchError(`${hostname} points to a private address, which is not allowed.`), '', 0);
    }
    if (options.all) return (callback as unknown as (e: null, a: LookupAddress[]) => void)(null, allowed);
    callback(null, allowed[0].address, allowed[0].family);
  });
};

const HEADERS = {
  // Many shops serve a bare page, or nothing, to clients that don't look like a browser.
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-IN,en;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
};

/** Fetches a URL and returns the final URL and the page as text. */
export async function fetchPage(url: string, opts: FetchOptions = {}): Promise<{ url: string; html: string }> {
  const { timeoutMs = 12_000, maxBytes = 5_000_000, maxRedirects = 5, allowPrivate = false } = opts;
  let current = url;
  for (let hop = 0; hop <= maxRedirects; hop++) {
    const target = parseTarget(current, allowPrivate);
    const res = await request(target, timeoutMs, allowPrivate);
    const status = res.statusCode ?? 0;
    if (status >= 300 && status < 400 && res.headers.location) {
      res.resume();
      current = new URL(res.headers.location, target).toString();
      continue;
    }
    if (status === 403 || status === 429 || status === 503) {
      res.resume();
      throw new FetchError(`The site refused the request (HTTP ${status}); it may block automatic reading.`);
    }
    if (status < 200 || status >= 300) {
      res.resume();
      throw new FetchError(`The page could not be loaded (HTTP ${status}).`);
    }
    const type = String(res.headers['content-type'] ?? '');
    if (type && !/html|xml/i.test(type)) {
      res.resume();
      throw new FetchError(`That link is not a web page (${type.split(';')[0]}).`);
    }
    const body = await readBody(res, maxBytes);
    const charset = type.match(/charset=([\w-]+)/i)?.[1] ?? 'utf-8';
    let decoder: TextDecoder;
    try {
      decoder = new TextDecoder(charset);
    } catch {
      decoder = new TextDecoder('utf-8');
    }
    return { url: current, html: decoder.decode(body) };
  }
  throw new FetchError('Too many redirects.');
}

function parseTarget(url: string, allowPrivate: boolean): URL {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    throw new FetchError('That is not a valid link.');
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') throw new FetchError('Only http and https links are supported.');
  if (u.username || u.password) throw new FetchError('Links with a username or password are not supported.');
  const host = u.hostname.replace(/^\[|\]$/g, '');
  if (!allowPrivate && (host === 'localhost' || host.endsWith('.localhost') || (isIP(host) && isBlockedAddress(host)))) {
    throw new FetchError('Links to private or local addresses are not allowed.');
  }
  return u;
}

function request(u: URL, timeoutMs: number, allowPrivate: boolean): Promise<http.IncomingMessage> {
  return new Promise((resolve, reject) => {
    const client = u.protocol === 'https:' ? https : http;
    const req = client.get(u, { headers: HEADERS, lookup: allowPrivate ? undefined : safeLookup, timeout: timeoutMs }, resolve);
    req.on('timeout', () => req.destroy(new FetchError('The site took too long to answer.')));
    req.on('error', (e) =>
      reject(e instanceof FetchError ? e : new FetchError(`Could not reach ${u.hostname}: ${(e as NodeJS.ErrnoException).code ?? e.message}`)),
    );
  });
}

function readBody(res: http.IncomingMessage, maxBytes: number): Promise<Buffer> {
  const encoding = String(res.headers['content-encoding'] ?? '').toLowerCase();
  const stream =
    encoding === 'gzip' ? res.pipe(zlib.createGunzip())
    : encoding === 'br' ? res.pipe(zlib.createBrotliDecompress())
    : encoding === 'deflate' ? res.pipe(zlib.createInflate())
    : res;
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    stream.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        res.destroy();
        reject(new FetchError('The page is too large.'));
        return;
      }
      chunks.push(chunk);
    });
    stream.on('end', () => resolve(Buffer.concat(chunks)));
    stream.on('error', (e) => reject(new FetchError(`The page could not be read: ${e.message}`)));
    res.on('error', (e) => reject(new FetchError(`The page could not be read: ${e.message}`)));
  });
}
