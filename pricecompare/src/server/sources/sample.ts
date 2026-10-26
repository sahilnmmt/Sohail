// A built-in catalogue of sample offers, so the app works without API keys.
// Prices, sellers and ratings are made up for demonstration; the app marks
// them as sample data. Links open the real site's search for the product.

import type { Listing, Seller } from '../../shared/types.ts';
import { titleTokens } from '../../shared/text.ts';
import type { Source } from './source.ts';

const SITES = {
  amazon: { site: 'amazon.in', siteName: 'Amazon', search: 'https://www.amazon.in/s?k=' },
  flipkart: { site: 'flipkart.com', siteName: 'Flipkart', search: 'https://www.flipkart.com/search?q=' },
  croma: { site: 'croma.com', siteName: 'Croma', search: 'https://www.croma.com/searchB?q=' },
  reliance: { site: 'reliancedigital.in', siteName: 'Reliance Digital', search: 'https://www.reliancedigital.in/products?q=' },
  tatacliq: { site: 'tatacliq.com', siteName: 'Tata CLiQ', search: 'https://www.tatacliq.com/search/?text=' },
  myntra: { site: 'myntra.com', siteName: 'Myntra', search: 'https://www.myntra.com/search?q=' },
} as const;

type SiteKey = keyof typeof SITES;

interface Row {
  at: SiteKey;
  title: string;
  price: number;
  mrp?: number;
  shipping?: number;
  seller: Seller;
  rating?: number;
  reviews?: number;
  days?: number;
  inStock?: boolean;
}

interface Product {
  brand: string;
  search: string;
  rows: Row[];
}

const fba = (name: string, rating?: number): Seller => ({ name, rating, fulfilledBySite: true });
const seller = (name: string, rating?: number): Seller => ({ name, rating });

const CATALOGUE: Product[] = [
  {
    brand: 'Samsung',
    search: 'Samsung Galaxy S24 256GB',
    rows: [
      { at: 'amazon', title: 'Samsung Galaxy S24 5G AI Smartphone (Onyx Black, 8GB, 256GB Storage)', price: 64999, mrp: 89999, shipping: 0, seller: fba('Appario Retail', 4.6), rating: 4.3, reviews: 8421, days: 2 },
      { at: 'flipkart', title: 'SAMSUNG Galaxy S24 5G (Onyx Black, 256 GB) (8 GB RAM)', price: 62999, mrp: 89999, shipping: 0, seller: fba('SuperComNet', 4.7), rating: 4.4, reviews: 21540, days: 3 },
      { at: 'croma', title: 'SAMSUNG Galaxy S24 5G (8GB RAM, 256GB, Onyx Black)', price: 66490, mrp: 89999, shipping: 0, seller: seller('Croma'), rating: 4.5, reviews: 312, days: 2 },
      { at: 'reliance', title: 'Samsung Galaxy S24 5G 256 GB, 8 GB RAM, Onyx Black, Mobile Phone', price: 65999, mrp: 89999, shipping: 0, seller: seller('Reliance Digital'), rating: 4.2, reviews: 96, days: 4 },
    ],
  },
  {
    brand: 'Apple',
    search: 'Apple iPhone 15 128GB',
    rows: [
      { at: 'amazon', title: 'Apple iPhone 15 (128 GB) - Black', price: 61900, mrp: 69900, shipping: 0, seller: fba('Clicktech Retail', 4.5), rating: 4.5, reviews: 15230, days: 1 },
      { at: 'flipkart', title: 'Apple iPhone 15 (Black, 128 GB)', price: 59999, mrp: 69900, shipping: 0, seller: fba('Flashstar Commerce', 4.6), rating: 4.6, reviews: 98110, days: 2 },
      { at: 'croma', title: 'Apple iPhone 15 (128GB, Black)', price: 62990, mrp: 69900, shipping: 0, seller: seller('Croma'), rating: 4.6, reviews: 1203, days: 2 },
      { at: 'tatacliq', title: 'Apple iPhone 15 128 GB Black', price: 63490, mrp: 69900, shipping: 99, seller: seller('Unicorn Infosolutions', 4.1), rating: 4.4, reviews: 87, days: 5 },
    ],
  },
  {
    brand: 'Apple',
    search: 'Apple iPhone 15 256GB',
    rows: [
      { at: 'amazon', title: 'Apple iPhone 15 (256 GB) - Black', price: 71900, mrp: 79900, shipping: 0, seller: fba('Clicktech Retail', 4.5), rating: 4.5, reviews: 4410, days: 1 },
      { at: 'flipkart', title: 'Apple iPhone 15 (Black, 256 GB)', price: 70999, mrp: 79900, shipping: 0, seller: fba('Flashstar Commerce', 4.6), rating: 4.6, reviews: 19870, days: 2 },
    ],
  },
  {
    brand: 'Sony',
    search: 'Sony WH-1000XM5',
    rows: [
      { at: 'amazon', title: 'Sony WH-1000XM5 Wireless Noise Cancelling Headphones, 30 Hrs Battery, Black', price: 26990, mrp: 34990, shipping: 0, seller: fba('Cocoblu Retail', 4.6), rating: 4.4, reviews: 11032, days: 1 },
      { at: 'flipkart', title: 'SONY WH-1000XM5 Bluetooth Headset (Black, On the Ear)', price: 27490, mrp: 34990, shipping: 0, seller: fba('Sony India', 4.8), rating: 4.5, reviews: 6234, days: 3 },
      { at: 'croma', title: 'SONY WH-1000XM5 Bluetooth Headphone with Mic (Black)', price: 29990, mrp: 34990, shipping: 0, seller: seller('Croma'), rating: 4.6, reviews: 540, days: 2 },
      { at: 'tatacliq', title: 'Sony WH-1000XM5 Wireless Headphones (Black)', price: 14999, mrp: 34990, shipping: 149, seller: seller('GadgetZone Deals', 3.2), rating: 3.9, reviews: 14, days: 7 },
      { at: 'reliance', title: 'Sony WH-1000XM5 Noise Cancelling Wireless Headphones, Black', price: 28990, mrp: 34990, shipping: 0, seller: seller('Reliance Digital'), rating: 4.5, reviews: 211, inStock: false },
    ],
  },
  {
    brand: 'boAt',
    search: 'boAt Airdopes 141',
    rows: [
      { at: 'amazon', title: 'boAt Airdopes 141 TWS Earbuds with 42H Playtime, ENx Tech, Bold Black', price: 1099, mrp: 4490, shipping: 0, seller: fba('Imagine Marketing Ltd', 4.4), rating: 3.9, reviews: 412300, days: 1 },
      { at: 'flipkart', title: 'boAt Airdopes 141 with 42 Hours Playback Bluetooth Headset (Bold Black, True Wireless)', price: 999, mrp: 4490, shipping: 40, seller: seller('Imagine Marketing', 4.3), rating: 4.0, reviews: 389120, days: 4 },
      { at: 'myntra', title: 'boAt Airdopes 141 True Wireless Earbuds - Bold Black', price: 1199, mrp: 4490, shipping: 0, seller: seller('Imagine Marketing Limited'), rating: 4.1, reviews: 2210, days: 5 },
    ],
  },
  {
    brand: 'OnePlus',
    search: 'OnePlus Nord CE4 128GB',
    rows: [
      { at: 'amazon', title: 'OnePlus Nord CE4 (Celadon Marble, 8GB RAM, 128GB Storage)', price: 22999, mrp: 24999, shipping: 0, seller: fba('Darshita Etel', 4.5), rating: 4.2, reviews: 23110, days: 2 },
      { at: 'flipkart', title: 'OnePlus Nord CE4 5G (Celadon Marble, 128 GB) (8 GB RAM)', price: 22499, mrp: 24999, shipping: 0, seller: seller('RetailNet', 4.4), rating: 4.3, reviews: 4120, days: 3 },
      { at: 'croma', title: 'OnePlus Nord CE4 5G (8GB RAM, 128GB, Celadon Marble)', price: 23999, mrp: 24999, shipping: 0, seller: seller('Croma'), rating: 4.4, reviews: 88, days: 3 },
    ],
  },
  {
    brand: 'Apple',
    search: 'Apple MacBook Air M3 13 inch',
    rows: [
      { at: 'amazon', title: 'Apple MacBook Air 13-inch Laptop with M3 chip: 13.6-inch Liquid Retina Display, 16GB RAM, 256GB SSD, Midnight', price: 94990, mrp: 114900, shipping: 0, seller: fba('Appario Retail', 4.6), rating: 4.6, reviews: 2104, days: 2 },
      { at: 'flipkart', title: 'Apple MacBook Air M3 (16 GB/256 GB SSD/macOS Sequoia) MC8K4HN/A 13.6 inch, Midnight', price: 92990, mrp: 114900, shipping: 0, seller: fba('Flashstar Commerce', 4.6), rating: 4.7, reviews: 3311, days: 3 },
      { at: 'croma', title: 'Apple MacBook Air 13" M3 (16GB RAM, 256GB SSD, Midnight) MC8K4HN/A', price: 97990, mrp: 114900, shipping: 0, seller: seller('Croma'), rating: 4.5, reviews: 140, days: 2 },
      { at: 'reliance', title: 'Apple MacBook Air MC8K4HN/A M3 Chip, 16GB, 256GB SSD, 13.6 inch, Midnight', price: 96490, mrp: 114900, shipping: 0, seller: seller('Reliance Digital'), rating: 4.4, reviews: 51, days: 4 },
    ],
  },
  {
    brand: 'Samsung',
    search: 'Samsung 55 inch Crystal 4K TV',
    rows: [
      { at: 'amazon', title: 'Samsung 138 cm (55 inches) Crystal 4K Vivid Ultra HD Smart LED TV UA55DUE77AKLXL (Black)', price: 41990, mrp: 70900, shipping: 0, seller: fba('Cocoblu Retail', 4.6), rating: 4.3, reviews: 5320, days: 3 },
      { at: 'flipkart', title: 'SAMSUNG Crystal 4K Vivid 138 cm (55 inch) Ultra HD (4K) LED Smart Tizen TV (UA55DUE77AKLXL)', price: 40990, mrp: 70900, shipping: 0, seller: seller('Samsung India', 4.8), rating: 4.3, reviews: 18200, days: 5 },
      { at: 'croma', title: 'SAMSUNG Crystal 4K Vivid 138 cm (55 inch) 4K Ultra HD LED Tizen TV, UA55DUE77AKLXL', price: 43490, mrp: 70900, shipping: 0, seller: seller('Croma'), rating: 4.2, reviews: 310, days: 4 },
      { at: 'reliance', title: 'Samsung 138 cm (55 inch) Crystal 4K Vivid Smart TV UA55DUE77AKLXL', price: 42990, mrp: 70900, shipping: 499, seller: seller('Reliance Digital'), rating: 4.1, reviews: 76, days: 6 },
    ],
  },
  {
    brand: 'Nike',
    search: 'Nike Revolution 7 running shoes',
    rows: [
      { at: 'amazon', title: 'Nike Mens Revolution 7 Running Shoe, Black/White', price: 3295, mrp: 3695, shipping: 0, seller: fba('RetailEZ Pvt Ltd', 4.4), rating: 4.2, reviews: 1830, days: 2 },
      { at: 'myntra', title: 'Nike Men Revolution 7 Running Shoes - Black', price: 3141, mrp: 3695, shipping: 0, seller: seller('Nike India', 4.7), rating: 4.4, reviews: 5200, days: 4 },
      { at: 'flipkart', title: 'NIKE Revolution 7 Running Shoes For Men (Black)', price: 3326, mrp: 3695, shipping: 0, seller: seller('SHREEDEEP SPORTS', 4.0), rating: 4.1, reviews: 960, days: 5 },
      { at: 'tatacliq', title: 'Nike Revolution 7 Black Running Shoes', price: 3695, mrp: 3695, seller: seller('Nike'), rating: 4.3, reviews: 40, days: 6 },
    ],
  },
];

/** Every sample offer, as listings. */
export function sampleListings(): Listing[] {
  return CATALOGUE.flatMap((p) =>
    p.rows.map((r) => ({
      site: SITES[r.at].site,
      siteName: SITES[r.at].siteName,
      title: r.title,
      url: SITES[r.at].search + encodeURIComponent(p.search),
      brand: p.brand,
      price: r.price,
      mrp: r.mrp,
      shipping: r.shipping,
      currency: 'INR',
      inStock: r.inStock ?? true,
      seller: r.seller,
      rating: r.rating,
      reviewCount: r.reviews,
      deliveryDays: r.days,
    })),
  );
}

/** True when every word of the query starts a word of the title (so "iph 15" finds "iPhone 15"). */
export function matchesQuery(title: string, query: string): boolean {
  const words = [...titleTokens(title)];
  const wanted = [...titleTokens(query)];
  return wanted.length > 0 && wanted.every((q) => words.some((w) => w.startsWith(q)));
}

export const sampleSource: Source = {
  id: 'sample',
  name: 'Sample catalogue',
  sample: true,
  async search(query) {
    const all = sampleListings();
    // An empty query lists everything so the app has something to show.
    return query.trim() ? all.filter((l) => matchesQuery(`${l.brand} ${l.title}`, query)) : all;
  },
};
