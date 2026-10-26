// Turns the listings for one product into a comparison: price differences,
// seller and rating, and a single "value" score.

import type { Badge, Comparison, Listing, Offer } from './types.ts';
import { formatMoney, titleSimilarity, variantOf } from './text.ts';

/**
 * A rating from few reviews says little, so ratings are pulled towards a
 * neutral PRIOR_RATING as if each had PRIOR_REVIEWS extra reviews at that
 * rating (a Bayesian average). 4.9 from 4 reviews then ranks below 4.5 from 5,000.
 */
export const PRIOR_REVIEWS = 50;
export const PRIOR_RATING = 3.5;

/** Weights of the value score; they add up to 1. */
export const WEIGHTS = { price: 0.6, rating: 0.3, seller: 0.1 };

/** An offer this far below the median price is flagged for a closer look. */
const SUSPICIOUSLY_CHEAP = 0.6;

const round2 = (n: number) => Math.round(n * 100) / 100;
const round1 = (n: number) => Math.round(n * 10) / 10;

function sellerScore(l: Listing): number {
  const s = l.seller;
  if (s?.rating !== undefined) return Math.max(s.rating / 5, s.fulfilledBySite ? 0.9 : 0);
  if (s?.fulfilledBySite) return 0.9;
  return 0.7; // unknown seller: neither rewarded nor heavily punished
}

function median(values: number[]): number {
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** Compares listings that are all the same product. Returns null for no listings. */
export function compareListings(all: Listing[]): Comparison | null {
  if (!all.length) return null;
  const warnings: string[] = [];

  // Compare within one currency: the one most listings use.
  const byCurrency = new Map<string, Listing[]>();
  for (const l of all) byCurrency.set(l.currency, [...(byCurrency.get(l.currency) ?? []), l]);
  const [currency, listings] = [...byCurrency.entries()].sort((a, b) => b[1].length - a[1].length)[0];
  for (const [other, ls] of byCurrency) {
    if (other !== currency) {
      warnings.push(`Left out ${ls.map((l) => l.siteName).join(', ')}: priced in ${other}, not ${currency}.`);
    }
  }

  const totals = listings.map((l) => l.price + (l.shipping ?? 0));
  const available = listings.filter((l) => l.inStock !== false);
  const pool = available.length ? available : listings;
  const lowest = Math.min(...pool.map((l) => l.price + (l.shipping ?? 0)));
  const highest = Math.max(...totals);

  const rated = listings.filter((l) => l.rating !== undefined);
  const reviewWeight = (l: Listing) => Math.max(l.reviewCount ?? 1, 1);
  const totalReviews = listings.reduce((sum, l) => sum + (l.reviewCount ?? 0), 0);
  const averageRating = rated.length
    ? rated.reduce((sum, l) => sum + l.rating! * reviewWeight(l), 0) / rated.reduce((s, l) => s + reviewWeight(l), 0)
    : undefined;

  const offers: Offer[] = listings.map((l) => {
    const total = l.price + (l.shipping ?? 0);
    const adjustedRating =
      l.rating === undefined
        ? undefined
        : (PRIOR_REVIEWS * PRIOR_RATING + (l.reviewCount ?? 0) * l.rating) / (PRIOR_REVIEWS + (l.reviewCount ?? 0));
    const valueScore =
      100 *
      (WEIGHTS.price * (lowest / total) +
        WEIGHTS.rating * ((adjustedRating ?? PRIOR_RATING) / 5) +
        WEIGHTS.seller * sellerScore(l)) *
      (l.inStock === false ? 0.5 : 1);
    return {
      ...l,
      total: round2(total),
      diff: round2(Math.max(total - lowest, 0)),
      diffPercent: round1((Math.max(total - lowest, 0) / lowest) * 100),
      discountPercent: l.mrp && l.mrp > l.price ? round1(((l.mrp - l.price) / l.mrp) * 100) : undefined,
      adjustedRating: adjustedRating === undefined ? undefined : round2(adjustedRating),
      valueScore: Math.min(100, Math.round(valueScore)),
      badges: [],
    };
  });

  // Cheapest first; out-of-stock offers last.
  offers.sort((a, b) => Number(a.inStock === false) - Number(b.inStock === false) || a.total - b.total);

  const award = (badge: Badge, candidates: Offer[], key: (o: Offer) => number | undefined) => {
    const scored = candidates.filter((o) => key(o) !== undefined);
    if (!scored.length) return;
    const best = Math.max(...scored.map((o) => key(o)!));
    for (const o of scored) if (key(o) === best) o.badges.push(badge);
  };
  const inStock = offers.filter((o) => o.inStock !== false);
  if (offers.length > 1) {
    award('cheapest', inStock, (o) => -o.total);
    award('top-rated', inStock, (o) => o.adjustedRating);
    award('best-value', inStock, (o) => o.valueScore);
  }
  for (const o of offers) {
    if (o.seller && ((o.seller.rating ?? 0) >= 4.5 || o.seller.fulfilledBySite)) o.badges.push('trusted-seller');
    if (o.inStock === false) o.badges.push('out-of-stock');
  }

  warnings.push(...checkSameProduct(offers));
  const unknownShipping = offers.filter((o) => o.shipping === undefined);
  if (unknownShipping.length && unknownShipping.length < offers.length) {
    warnings.push(
      `Delivery charge not known for ${unknownShipping.map((o) => o.siteName).join(', ')}; its price is compared without delivery.`,
    );
  }
  const mid = median(offers.map((o) => o.total));
  for (const o of offers) {
    if (offers.length > 2 && o.total < SUSPICIOUSLY_CHEAP * mid) {
      warnings.push(
        `${o.siteName} is ${Math.round((1 - o.total / mid) * 100)}% below the typical price (${formatMoney(mid, currency)}). ` +
          'Check the seller, warranty and that it is the same item.',
      );
    }
  }

  const representative = [...offers].sort((a, b) => (b.reviewCount ?? 0) - (a.reviewCount ?? 0))[0];
  return {
    title: representative.title,
    image: offers.find((o) => o.image)?.image,
    currency,
    offers,
    summary: {
      sites: new Set(offers.map((o) => o.site)).size,
      lowest: round2(lowest),
      highest: round2(highest),
      spread: round2(highest - lowest),
      spreadPercent: round1(((highest - lowest) / lowest) * 100),
      averageRating: averageRating === undefined ? undefined : round2(averageRating),
      totalReviews,
    },
    warnings,
  };
}

/** Warnings for offers that may be a different variant or product than the rest. */
function checkSameProduct(offers: Offer[]): string[] {
  const warnings: string[] = [];
  const variants = offers.map((o) => variantOf(o.title));
  const differing = (key: 'storage' | 'size' | 'colour') => {
    const seen = new Map<string, string[]>();
    variants.forEach((v, i) => {
      const value = key === 'storage' ? v.storage.join(' + ') : v[key];
      if (value) seen.set(value, [...(seen.get(value) ?? []), offers[i].siteName]);
    });
    return seen.size > 1 ? [...seen].map(([value, sites]) => `${value} (${sites.join(', ')})`).join(' vs ') : undefined;
  };
  const storage = differing('storage');
  if (storage) warnings.push(`Different storage/memory listed: ${storage}.`);
  const size = differing('size');
  if (size) warnings.push(`Different sizes listed: ${size.replace(/IN\b/g, '"')}.`);
  const colour = differing('colour');
  if (colour) warnings.push(`Different colours listed: ${colour}. Prices can differ by colour.`);

  if (offers.length > 1) {
    for (const o of offers) {
      const best = Math.max(...offers.filter((p) => p !== o).map((p) => titleSimilarity(o.title, p.title)));
      if (best < 0.35) warnings.push(`The ${o.siteName} listing may be a different product: "${o.title}".`);
    }
  }
  return warnings;
}
