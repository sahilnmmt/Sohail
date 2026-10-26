// Groups listings from different sites into products.

import type { Listing } from './types.ts';
import { modelCodes, modelConflict, titleSimilarity, variantConflict, variantOf } from './text.ts';

/** Titles at least this alike (0–1) are treated as the same product. */
export const SAME_PRODUCT = 0.6;

function codesOf(l: Listing): Set<string> {
  const codes = modelCodes(l.title);
  if (l.model) codes.add(l.model.toUpperCase().replace(/[-/\s]/g, ''));
  return codes;
}

/** How likely two listings are the same product, 0–1. 0 when they are clearly different. */
export function sameProductScore(a: Listing, b: Listing): number {
  if (variantConflict(variantOf(a.title), variantOf(b.title))) return 0;
  if (a.brand && b.brand && a.brand.toLowerCase() !== b.brand.toLowerCase()) return 0;
  const ca = codesOf(a);
  const cb = codesOf(b);
  for (const c of ca) if (cb.has(c)) return 1;
  if (modelConflict(a.title, b.title)) return 0;
  return titleSimilarity(a.title, b.title);
}

/**
 * Splits listings into groups that are each one product. A listing joins the
 * group it best matches; groups with more sites come first.
 */
export function groupListings(listings: Listing[]): Listing[][] {
  const groups: Listing[][] = [];
  for (const listing of listings) {
    let best: Listing[] | undefined;
    let bestScore = 0;
    for (const group of groups) {
      // Must plausibly match every member, and best-match at least one strongly.
      const scores = group.map((m) => sameProductScore(listing, m));
      if (scores.some((s) => s === 0)) continue;
      const score = Math.max(...scores);
      if (score >= SAME_PRODUCT && score > bestScore) {
        best = group;
        bestScore = score;
      }
    }
    if (best) best.push(listing);
    else groups.push([listing]);
  }
  const sites = (g: Listing[]) => new Set(g.map((l) => l.site)).size;
  return groups.sort((a, b) => sites(b) - sites(a));
}
