// Reads a product page's HTML into a Listing.
//
// Most shops describe their products for search engines with schema.org data
// (JSON-LD or microdata) and Open Graph tags, so one generic reader covers most
// sites. Amazon has little of that, so it also gets a reader of its own.

import { parse, type HTMLElement } from 'node-html-parser';
import type { Listing } from '../shared/types.ts';
import { detectCurrency, parseCount, parsePrice, parseRating, siteFromUrl } from '../shared/text.ts';

export class ExtractError extends Error {}

type Partial = Omit<Listing, 'site' | 'siteName' | 'url' | 'price' | 'currency' | 'title'> & {
  title?: string;
  price?: number;
  currency?: string;
};

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const asArray = <T>(v: T | T[] | undefined): T[] => (v === undefined ? [] : Array.isArray(v) ? v : [v]);
const text = (v: unknown): string | undefined => {
  if (typeof v === 'string') return v.trim() || undefined;
  if (typeof v === 'number') return String(v);
  if (isObject(v)) return text(v.name ?? v.url ?? v['@value']);
  if (Array.isArray(v)) return text(v[0]);
  return undefined;
};
const hasType = (o: Json, type: string) =>
  asArray(o['@type'] as string | string[]).some((t) => typeof t === 'string' && t.replace(/^.*[/#]/, '') === type);

/** Every object in a JSON-LD document, including nested and @graph ones. */
function walk(node: unknown, out: Json[] = []): Json[] {
  if (Array.isArray(node)) for (const n of node) walk(n, out);
  else if (isObject(node)) {
    out.push(node);
    for (const v of Object.values(node)) if (typeof v === 'object') walk(v, out);
  }
  return out;
}

function fromJsonLd(root: HTMLElement): Partial {
  const objects: Json[] = [];
  for (const script of root.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      walk(JSON.parse(script.textContent.trim()), objects);
    } catch {
      // Some sites ship broken JSON-LD; the other readers still apply.
    }
  }
  const product = objects.find((o) => hasType(o, 'Product') || hasType(o, 'ProductGroup'));
  if (!product) return {};

  const offers = walk(product.offers).filter((o) => hasType(o, 'Offer') || hasType(o, 'AggregateOffer'));
  // Prefer a concrete offer that is in stock; otherwise the lowest price shown.
  const priced = offers
    .map((o) => ({ o, price: parsePrice(o.price ?? o.lowPrice ?? (isObject(o.priceSpecification) ? o.priceSpecification.price : undefined)) }))
    .filter((x) => x.price !== undefined)
    .sort((a, b) => Number(/OutOfStock/i.test(String(a.o.availability))) - Number(/OutOfStock/i.test(String(b.o.availability))) || a.price! - b.price!);
  const offer = priced[0]?.o;
  const rating = walk(product.aggregateRating).find((o) => o.ratingValue !== undefined);
  const shipping = offer && walk(offer.shippingDetails).find((o) => o.shippingRate !== undefined);
  const availability = offer && text(offer.availability);
  const sellerName = offer && text(offer.seller);
  const best = rating && parsePrice(rating.bestRating);

  return {
    title: text(product.name),
    image: text(product.image),
    brand: text(product.brand),
    model: text(product.mpn ?? product.gtin13 ?? product.gtin ?? product.gtin12 ?? product.model),
    price: priced[0]?.price,
    currency: offer && (text(offer.priceCurrency) ?? (isObject(offer.priceSpecification) ? text(offer.priceSpecification.priceCurrency) : undefined)),
    mrp: offer && listPrice(offer),
    shipping: shipping ? parsePrice(isObject(shipping.shippingRate) ? shipping.shippingRate.value : shipping.shippingRate) : undefined,
    inStock: availability ? !/OutOfStock|SoldOut|Discontinued/i.test(availability) : undefined,
    seller: sellerName ? { name: sellerName } : undefined,
    rating: rating ? parseRating(rating.ratingValue, best && best > 0 ? best : 5) : undefined,
    reviewCount: rating ? parseCount(rating.reviewCount ?? rating.ratingCount) : undefined,
  };
}

/** The MRP / list price an offer is discounted from, when it says. */
function listPrice(offer: Json): number | undefined {
  const spec = walk(offer.priceSpecification).find((s) => /ListPrice|StrikethroughPrice|MSRP/i.test(String(s.priceType)));
  return parsePrice(spec?.price);
}

function fromMicrodata(root: HTMLElement): Partial {
  const prop = (name: string) => {
    const el = root.querySelector(`[itemprop="${name}"]`);
    return el ? (el.getAttribute('content') ?? el.getAttribute('href') ?? el.textContent).trim() || undefined : undefined;
  };
  const availability = prop('availability');
  return {
    title: root.querySelector('[itemtype*="schema.org/Product"] [itemprop="name"]')?.textContent.trim() || undefined,
    price: parsePrice(prop('price')),
    currency: prop('priceCurrency'),
    rating: parseRating(prop('ratingValue'), parsePrice(prop('bestRating')) ?? 5),
    reviewCount: parseCount(prop('reviewCount') ?? prop('ratingCount')),
    brand: prop('brand'),
    inStock: availability ? !/OutOfStock|SoldOut/i.test(availability) : undefined,
  };
}

function fromMeta(root: HTMLElement): Partial {
  const meta = (...names: string[]) => {
    for (const n of names) {
      const v = root.querySelector(`meta[property="${n}"], meta[name="${n}"]`)?.getAttribute('content')?.trim();
      if (v) return v;
    }
    return undefined;
  };
  return {
    title: meta('og:title', 'twitter:title') ?? (root.querySelector('title')?.textContent.trim() || undefined),
    image: meta('og:image', 'twitter:image'),
    price: parsePrice(meta('product:price:amount', 'og:price:amount', 'twitter:data1')),
    currency: meta('product:price:currency', 'og:price:currency'),
    brand: meta('product:brand', 'og:brand'),
  };
}

function fromAmazon(root: HTMLElement): Partial {
  const q = (sel: string) => root.querySelector(sel)?.textContent.replace(/\s+/g, ' ').trim() || undefined;
  const priceText =
    q('#corePriceDisplay_desktop_feature_div .priceToPay .a-offscreen') ??
    q('#corePrice_feature_div .a-offscreen') ??
    q('#corePrice_desktop .a-offscreen') ??
    q('#priceblock_dealprice') ??
    q('#priceblock_ourprice') ??
    q('.a-price .a-offscreen');
  const mrpText = q('#corePriceDisplay_desktop_feature_div .basisPrice .a-offscreen') ?? q('.basisPrice .a-offscreen');
  const shipsFrom = q('#fulfillerInfoFeature_feature_div') ?? q('#tabular-buybox') ?? q('#merchant-info') ?? '';
  const sellerName = q('#sellerProfileTriggerId') ?? q('#merchantInfoFeature_feature_div .offer-display-feature-text-message');
  const availability = q('#availability');
  return {
    title: q('#productTitle'),
    image: root.querySelector('#landingImage')?.getAttribute('data-old-hires') || root.querySelector('#landingImage')?.getAttribute('src'),
    price: parsePrice(priceText),
    currency: priceText ? detectCurrency(priceText) : undefined,
    mrp: parsePrice(mrpText),
    rating: parseRating(root.querySelector('#acrPopover')?.getAttribute('title') ?? q('#acrPopover .a-icon-alt')),
    reviewCount: parseCount(q('#acrCustomerReviewText')),
    brand: q('#bylineInfo')?.replace(/^(Visit the|Brand:)\s*/i, '').replace(/\s*Store$/i, ''),
    seller: sellerName ? { name: sellerName, fulfilledBySite: /Amazon/i.test(shipsFrom) } : undefined,
    inStock: availability ? !/unavailable|out of stock/i.test(availability) : undefined,
  };
}

const SITE_READERS: Record<string, (root: HTMLElement) => Partial> = {
  'amazon.in': fromAmazon,
  'amazon.com': fromAmazon,
  'amazon.co.uk': fromAmazon,
};

/** The currency a site's prices are in when the page doesn't say: by country domain, else INR. */
function currencyOfSite(site: string): string {
  if (/\.(in)$/.test(site)) return 'INR';
  if (/\.uk$/.test(site)) return 'GBP';
  if (/\.(de|fr|it|es|nl|ie)$/.test(site)) return 'EUR';
  if (/^(amazon|walmart|bestbuy|ebay|target)\.com$/.test(site)) return 'USD';
  return 'INR';
}

/** True when the page is a captcha or "access denied" page rather than the product. */
export function looksBlocked(html: string): boolean {
  return /captcha|robot check|access denied|are you a human|unusual traffic|enable javascript and cookies/i.test(html.slice(0, 20000));
}

/** Reads a product page. Throws ExtractError when it has no title or price. */
export function extractListing(html: string, url: string): Listing {
  const root = parse(html, { blockTextElements: { script: true, style: false, noscript: false, pre: true } });
  const { site, siteName } = siteFromUrl(url);
  const readers = [fromJsonLd, SITE_READERS[site], fromMicrodata, fromMeta].filter((r) => r !== undefined);
  const merged: Partial = {};
  for (const read of readers) {
    for (const [key, value] of Object.entries(read(root))) {
      if (value !== undefined && (merged as Json)[key] === undefined) (merged as Json)[key] = value;
    }
  }
  if (merged.price === undefined || !merged.title) {
    if (looksBlocked(html)) {
      throw new ExtractError(`${siteName} blocked automatic reading (it asked for a captcha). Add this offer by hand.`);
    }
    throw new ExtractError(`Couldn't find ${merged.title ? 'a price' : 'a product'} on this ${siteName} page.`);
  }
  if (merged.mrp !== undefined && merged.mrp <= merged.price) delete merged.mrp;
  return {
    site,
    siteName,
    url,
    ...merged,
    title: merged.title.replace(/\s+/g, ' '),
    price: merged.price,
    currency: (merged.currency ?? currencyOfSite(site)).toUpperCase(),
  };
}
