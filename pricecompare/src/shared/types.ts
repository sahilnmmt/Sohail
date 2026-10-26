// Shared by the server and the browser. Plain data only, so it travels as JSON.

/** One offer for a product on one site. */
export interface Listing {
  /** Stable id of the site, e.g. `amazon.in`. */
  site: string;
  /** Display name of the site, e.g. `Amazon`. */
  siteName: string;
  title: string;
  url: string;
  image?: string;
  brand?: string;
  /** Manufacturer model number, GTIN or MPN when the site gives one. */
  model?: string;
  /** Selling price, in `currency`. */
  price: number;
  /** List price / MRP, when the site shows a discount from it. */
  mrp?: number;
  /** Delivery charge; 0 for free delivery, absent when unknown. */
  shipping?: number;
  /** ISO 4217 code, e.g. `INR`. */
  currency: string;
  inStock?: boolean;
  seller?: Seller;
  /** Product rating out of 5 on this site. */
  rating?: number;
  reviewCount?: number;
  deliveryDays?: number;
}

export interface Seller {
  name: string;
  /** Seller rating out of 5, when the site shows one. */
  rating?: number;
  /** The site itself ships it: Fulfilled by Amazon, Flipkart Assured and so on. */
  fulfilledBySite?: boolean;
}

/** A listing plus how it compares with the others for the same product. */
export interface Offer extends Listing {
  /** Price plus known shipping. */
  total: number;
  /** How much more than the cheapest offer, in currency and percent. 0 for the cheapest. */
  diff: number;
  diffPercent: number;
  /** Percent off MRP, when known. */
  discountPercent?: number;
  /** Rating adjusted for how many reviews back it (see compare.ts). */
  adjustedRating?: number;
  /** 0–100; higher is better. See compare.ts for the formula. */
  valueScore: number;
  badges: Badge[];
}

export type Badge = 'cheapest' | 'top-rated' | 'best-value' | 'trusted-seller' | 'out-of-stock';

/** One product with its offers from every site, cheapest first. */
export interface Comparison {
  title: string;
  image?: string;
  currency: string;
  offers: Offer[];
  summary: {
    sites: number;
    lowest: number;
    highest: number;
    /** Highest minus lowest total price, in currency and percent of the lowest. */
    spread: number;
    spreadPercent: number;
    averageRating?: number;
    totalReviews: number;
  };
  /** Things the shopper should double-check, e.g. a listing that may be a different variant. */
  warnings: string[];
}

export interface SearchResponse {
  query: string;
  products: Comparison[];
  /** Sites that could not be searched, with the reason. */
  errors: SourceError[];
  /** True when any result came from built-in sample data rather than a live site. */
  sample: boolean;
}

export interface CompareLinksRequest {
  urls: string[];
  /** Offers typed in by hand, for sites that block automatic reading. */
  manual?: Listing[];
}

export interface CompareLinksResponse {
  comparison: Comparison | null;
  /** Each link that could not be read, with the reason. */
  errors: SourceError[];
  listings: Listing[];
}

export interface SourceError {
  source: string;
  message: string;
}
