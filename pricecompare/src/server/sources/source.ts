import type { Listing } from '../../shared/types.ts';

/**
 * Somewhere products can be searched: a shop's official API, a price feed, or
 * the built-in sample catalogue. Add one by implementing this and listing it in
 * sources/index.ts.
 */
export interface Source {
  id: string;
  name: string;
  /** True when results are not live prices (shown as a notice in the app). */
  sample: boolean;
  search(query: string, signal: AbortSignal): Promise<Listing[]>;
}
