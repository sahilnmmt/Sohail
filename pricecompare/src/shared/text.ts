// Text helpers: prices, currencies, site names and product titles.

const CURRENCY_SYMBOLS: [RegExp, string][] = [
  [/₹|\brs\.?|\binr\b/i, 'INR'],
  [/€|\beur\b/i, 'EUR'],
  [/£|\bgbp\b/i, 'GBP'],
  [/\$|\busd\b/i, 'USD'],
];

/** The currency a price string is written in, if it says. */
export function detectCurrency(text: string): string | undefined {
  return CURRENCY_SYMBOLS.find(([re]) => re.test(text))?.[1];
}

/**
 * Reads a price such as `₹1,29,999.00`, `Rs. 999`, `$1,299.99` or `1.299,99 €`.
 * Returns undefined when there is no usable number.
 */
export function parsePrice(value: unknown): number | undefined {
  if (typeof value === 'number') return Number.isFinite(value) && value >= 0 ? value : undefined;
  if (typeof value !== 'string') return undefined;
  const match = value.replace(/\s/g, '').match(/\d[\d.,]*/);
  if (!match) return undefined;
  let digits = match[0].replace(/[.,]$/, '');
  const lastComma = digits.lastIndexOf(',');
  const lastDot = digits.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // Whichever separator comes last is the decimal point.
    digits = lastComma > lastDot ? digits.replace(/\./g, '').replace(',', '.') : digits.replace(/,/g, '');
  } else if (lastComma >= 0) {
    // `1,299` and `1,29,999` group thousands; `12,50` is a decimal comma.
    digits = /,\d{3}$/.test(digits) ? digits.replace(/,/g, '') : digits.replace(/,/g, '.');
  } else if ((digits.match(/\./g) ?? []).length > 1) {
    digits = digits.replace(/\./g, ''); // `1.299.000`
  }
  const n = Number(digits);
  return Number.isFinite(n) ? n : undefined;
}

/** Reads a rating such as `4.3 out of 5 stars` or `4,3`. Values above 5 are rejected. */
export function parseRating(value: unknown, best = 5): number | undefined {
  const n = typeof value === 'number' ? value : Number(String(value ?? '').replace(',', '.').match(/\d+(\.\d+)?/)?.[0]);
  if (!Number.isFinite(n) || n < 0 || !best) return undefined;
  const outOf5 = (n / best) * 5;
  return outOf5 <= 5 ? Math.round(outOf5 * 100) / 100 : undefined;
}

/** Reads a count such as `12,345 ratings` or `1.2k`. */
export function parseCount(value: unknown): number | undefined {
  if (typeof value === 'number') return Number.isFinite(value) ? Math.round(value) : undefined;
  const m = String(value ?? '').replace(/,/g, '').match(/(\d+(?:\.\d+)?)\s*([kKmM]|lakh)?/);
  if (!m) return undefined;
  const scale = { k: 1e3, K: 1e3, m: 1e6, M: 1e6, lakh: 1e5 }[m[2] ?? ''] ?? 1;
  return Math.round(Number(m[1]) * scale);
}

const SITES: Record<string, string> = {
  'amazon.in': 'Amazon',
  'amazon.com': 'Amazon',
  'amazon.co.uk': 'Amazon',
  'flipkart.com': 'Flipkart',
  'croma.com': 'Croma',
  'reliancedigital.in': 'Reliance Digital',
  'tatacliq.com': 'Tata CLiQ',
  'vijaysales.com': 'Vijay Sales',
  'myntra.com': 'Myntra',
  'ajio.com': 'AJIO',
  'nykaa.com': 'Nykaa',
  'snapdeal.com': 'Snapdeal',
  'jiomart.com': 'JioMart',
  'meesho.com': 'Meesho',
  'walmart.com': 'Walmart',
  'bestbuy.com': 'Best Buy',
  'ebay.com': 'eBay',
};

/** Site id (the registrable domain) and display name for a product URL. */
export function siteFromUrl(url: string): { site: string; siteName: string } {
  let host = '';
  try {
    host = new URL(url).hostname.toLowerCase().replace(/^www\.|^m\./, '');
  } catch {
    return { site: 'unknown', siteName: 'Unknown site' };
  }
  const known = Object.keys(SITES).find((d) => host === d || host.endsWith(`.${d}`));
  if (known) return { site: known, siteName: SITES[known] };
  const name = host.split('.').slice(-2, -1)[0] ?? host;
  return { site: host, siteName: name.charAt(0).toUpperCase() + name.slice(1) };
}

// ---- titles --------------------------------------------------------------------

const STOPWORDS = new Set(
  ('a an and the of for with by in on to from new latest edition version model pack combo free buy online best price india ' +
    'mobile phone smartphone unlocked dual sim ram rom storage memory gb').split(' '),
);

/** Words that name a different model in the same line: an iPhone 15 Pro is not an iPhone 15. */
const LINE_WORDS = new Set(['pro', 'max', 'plus', 'ultra', 'mini', 'lite', 'fe', 'neo', 'slim', 'se', 'prime']);

const UNITS: Record<string, string> = { inches: 'inch', in: 'inch', '"': 'inch', '”': 'inch', hrs: 'h', hours: 'h', hr: 'h' };

/**
 * Lower-case words of a title in order, without filler words. A number and its
 * unit become one word (`8 GB` → `8gb`, `55 inches` → `55inch`), and `men's` → `men`.
 */
export function titleWords(title: string): string[] {
  const words = title
    .toLowerCase()
    .replace(/(\d+(?:\.\d+)?)\s*-?\s*(gb|tb|mb|inch(?:es)?|in\b|"|”|mp|mah|hz|w\b|cm|mm|kg|ml|hours?|hrs?)/g, (_, n, u) => ` ${n}${UNITS[u] ?? u} `)
    .replace(/'s\b/g, '')
    .replace(/[^\p{L}\p{N}.]+/gu, ' ')
    .replace(/(?<!\d)\.|\.(?!\d)/g, ' ')
    .split(' ')
    .map((t) => (t === 'mens' ? 'men' : t === 'womens' ? 'women' : t))
    .filter((t) => t && !STOPWORDS.has(t));
  return [...new Set(words)];
}

export function titleTokens(title: string): Set<string> {
  return new Set(titleWords(title));
}

/** A number-and-unit word such as `256gb`, `5g` or `4k`: a spec, not a model name. */
const isSpec = (t: string) => /^\d+(\.\d+)?(gb|tb|mb|inch|mp|mah|hz|w|cm|mm|kg|ml|h|g|k|p)$/.test(t);

/**
 * Why two titles name different models, or undefined. Looks at the model
 * numbers near the start of the title (`iPhone 15` vs `iPhone 14`) and at line
 * words (`Pro`, `Max`, `Ultra`…) that only one title has.
 */
export function modelConflict(a: string, b: string): string | undefined {
  const wa = titleWords(a);
  const wb = titleWords(b);
  const head = (w: string[]) => new Set(w.slice(0, 5).filter((t) => /\d/.test(t) && !isSpec(t)));
  const ha = head(wa);
  const hb = head(wb);
  if (ha.size && hb.size && ![...ha].some((t) => hb.has(t)) && ![...ha].some((t) => wb.includes(t)) && ![...hb].some((t) => wa.includes(t))) {
    return `${[...ha].join(' ')} vs ${[...hb].join(' ')}`;
  }
  const line = (w: string[]) => new Set(w.filter((t) => LINE_WORDS.has(t)));
  const la = line(wa);
  const lb = line(wb);
  const onlyA = [...la].filter((t) => !lb.has(t));
  const onlyB = [...lb].filter((t) => !la.has(t));
  if (onlyA.length || onlyB.length) return `${[...la].join(' ') || 'standard'} vs ${[...lb].join(' ') || 'standard'}`;
  return undefined;
}

/**
 * How alike two titles are, 0–1. Words near the start count more, since
 * titles lead with brand and model and trail off into marketing. Sites pad
 * titles differently ("… (Titanium Grey, 256 GB) | Galaxy AI | 50MP Camera"),
 * so a short title mostly contained in a long one also scores well.
 */
export function titleSimilarity(a: string, b: string): number {
  const wa = titleWords(a);
  const wb = titleWords(b);
  if (!wa.length || !wb.length) return 0;
  const weight = (i: number) => 1 / (1 + 0.2 * i);
  const ib = new Map(wb.map((t, i) => [t, i]));
  let sharedA = 0;
  let sharedB = 0;
  let count = 0;
  wa.forEach((t, i) => {
    const j = ib.get(t);
    if (j === undefined) return;
    sharedA += weight(i);
    sharedB += weight(j);
    count++;
  });
  if (count < 2 && Math.min(wa.length, wb.length) > 1) return 0;
  const totalA = wa.reduce((s, _, i) => s + weight(i), 0);
  const totalB = wb.reduce((s, _, i) => s + weight(i), 0);
  const dice = (sharedA + sharedB) / (totalA + totalB);
  const coverage = Math.max(sharedA / totalA, sharedB / totalB);
  return Math.min(1, Math.max(dice, 0.85 * coverage));
}

/** Model numbers in a title: tokens mixing letters and digits, like `SM-S921B` or `WH-1000XM5`. */
export function modelCodes(text: string): Set<string> {
  const codes = new Set<string>();
  for (const raw of text.toUpperCase().match(/[A-Z0-9][A-Z0-9\-/]{3,}[A-Z0-9]/g) ?? []) {
    const code = raw.replace(/[-/]/g, '');
    if (code.length < 5 || !/[A-Z]/.test(code) || !/\d/.test(code)) continue;
    if (/^\d+(GB|TB|MB|MP|MAH|HZ|W|MM|CM|G|K|P|ML|L|KG)$/.test(code)) continue; // a spec, not a model
    codes.add(code);
  }
  return codes;
}

export interface Variant {
  /** Memory and storage sizes, e.g. `8GB`, `256GB`. */
  storage: string[];
  /** Screen or product size, e.g. `55IN`. */
  size?: string;
  colour?: string;
}

const COLOURS = [
  'black', 'white', 'silver', 'grey', 'gray', 'gold', 'blue', 'red', 'green', 'pink', 'purple', 'violet',
  'yellow', 'orange', 'titanium', 'graphite', 'midnight', 'starlight', 'cream', 'beige', 'brown', 'navy',
];

/** The variant a title describes: storage, size and colour. */
export function variantOf(title: string): Variant {
  const lower = title.toLowerCase();
  const storage = [...lower.matchAll(/(\d+)\s*(gb|tb)\b/g)].map((m) => `${m[1]}${m[2].toUpperCase()}`);
  const size = lower.match(/(\d+(?:\.\d+)?)\s*-?\s*(?:inch(?:es)?|in\b|"|”)/)?.[1];
  const colour = COLOURS.find((c) => new RegExp(`\\b${c}\\b`).test(lower));
  return {
    storage: [...new Set(storage)].sort(),
    size: size ? `${size}IN` : undefined,
    colour: colour === 'gray' ? 'grey' : colour,
  };
}

/** Why two titles are different variants (storage or size), or undefined if they may be the same. */
export function variantConflict(a: Variant, b: Variant): string | undefined {
  if (a.storage.length && b.storage.length && a.storage.join() !== b.storage.join()) {
    return `${a.storage.join(' + ')} vs ${b.storage.join(' + ')}`;
  }
  // 13" and 13.6" are the same laptop described two ways; 55" and 65" are not.
  if (a.size && b.size && Math.abs(parseFloat(a.size) - parseFloat(b.size)) >= 1) return `${a.size.replace('IN', '"')} vs ${b.size.replace('IN', '"')}`;
  return undefined;
}

export function formatMoney(amount: number, currency: string): string {
  const locale = currency === 'INR' ? 'en-IN' : 'en';
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      maximumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}
