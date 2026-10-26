import './style.css';
import type { Badge, CompareLinksResponse, Comparison, Listing, Offer, SearchResponse, SourceError } from '../shared/types.ts';
import { formatMoney } from '../shared/text.ts';

// ---- helpers -------------------------------------------------------------------

/** Escapes text for HTML. Every value from a shop or the user goes through this. */
function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector(sel) as T;
const safeUrl = (url: string) => (/^https?:\/\//i.test(url) ? url : '');

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init);
  const body = await res.json().catch(() => ({ error: `The server answered ${res.status}.` }));
  if (!res.ok) throw new Error(body.error ?? `The server answered ${res.status}.`);
  return body as T;
}

const BADGES: Record<Badge, string> = {
  cheapest: 'Cheapest',
  'top-rated': 'Top rated',
  'best-value': 'Best value',
  'trusted-seller': 'Trusted seller',
  'out-of-stock': 'Out of stock',
};

const stars = (rating: number) => `<span class="star" aria-hidden="true">★</span>${rating.toFixed(1)}`;

// ---- comparison rendering ---------------------------------------------------------

type SortKey = 'price' | 'rating' | 'value';

function sortOffers(offers: Offer[], key: SortKey): Offer[] {
  const out = [...offers];
  const stock = (o: Offer) => Number(o.inStock === false);
  if (key === 'rating') out.sort((a, b) => stock(a) - stock(b) || (b.adjustedRating ?? -1) - (a.adjustedRating ?? -1));
  else if (key === 'value') out.sort((a, b) => stock(a) - stock(b) || b.valueScore - a.valueScore);
  else out.sort((a, b) => stock(a) - stock(b) || a.total - b.total);
  return out;
}

function offerRow(o: Offer, c: Comparison): string {
  const money = (n: number) => formatMoney(n, c.currency);
  // The bar shows where the price sits between the lowest and the highest.
  const barWidth = c.summary.spread ? 6 + (94 * (o.total - c.summary.lowest)) / c.summary.spread : 6;
  const link = safeUrl(o.url);
  const seller = o.seller
    ? `<div class="seller-name">${esc(o.seller.name)}</div>
       <div class="muted">${o.seller.rating !== undefined ? `${stars(o.seller.rating)} seller` : 'Seller rating n/a'}${
         o.seller.fulfilledBySite ? ` · <span class="tag">Shipped by ${esc(o.siteName)}</span>` : ''
       }</div>`
    : '<span class="muted">Not shown</span>';
  const rating =
    o.rating !== undefined
      ? `<div>${stars(o.rating)}</div><div class="muted">${(o.reviewCount ?? 0).toLocaleString('en-IN')} reviews</div>`
      : '<span class="muted">No rating</span>';
  const delivery =
    o.shipping === undefined ? '<span class="muted">Delivery ?</span>'
    : o.shipping === 0 ? 'Free delivery'
    : `+ ${money(o.shipping)} delivery`;
  return `
    <tr class="${o.badges.includes('cheapest') ? 'is-cheapest' : ''} ${o.inStock === false ? 'is-oos' : ''}">
      <td data-label="Shop">
        <div class="site">${esc(o.siteName)}</div>
        <div class="badges">${o.badges.map((b) => `<span class="badge badge-${b}">${BADGES[b]}</span>`).join('')}</div>
      </td>
      <td data-label="Price">
        <div class="price">${money(o.price)}</div>
        ${o.mrp ? `<div class="muted"><s>${money(o.mrp)}</s> ${o.discountPercent ? `· ${o.discountPercent}% off` : ''}</div>` : ''}
        <div class="muted">${delivery}${o.deliveryDays !== undefined ? ` · ${o.deliveryDays} day${o.deliveryDays === 1 ? '' : 's'}` : ''}</div>
      </td>
      <td data-label="vs cheapest">
        <div class="${o.diff ? 'diff-up' : 'diff-zero'}">${o.diff ? `+ ${money(o.diff)} <span class="muted">(+${o.diffPercent}%)</span>` : 'Lowest price'}</div>
        <div class="bar" aria-hidden="true"><span style="width:${barWidth.toFixed(1)}%"></span></div>
      </td>
      <td data-label="Seller">${seller}</td>
      <td data-label="Rating">${rating}</td>
      <td data-label="Value">
        <div class="score" title="Value score out of 100"><span style="--score:${o.valueScore}">${o.valueScore}</span></div>
      </td>
      <td data-label="">${link ? `<a class="go" href="${esc(link)}" target="_blank" rel="noopener noreferrer nofollow">View on ${esc(o.siteName)} ↗</a>` : ''}</td>
    </tr>`;
}

function comparisonCard(c: Comparison, index: number): string {
  const money = (n: number) => formatMoney(n, c.currency);
  const s = c.summary;
  const single = c.offers.length === 1;
  return `
    <article class="card product" data-index="${index}">
      <div class="product-head">
        ${c.image && safeUrl(c.image) ? `<img src="${esc(c.image)}" alt="" loading="lazy" referrerpolicy="no-referrer" />` : ''}
        <div>
          <h2>${esc(c.title)}</h2>
          <dl class="stats">
            <div><dt>Lowest</dt><dd>${money(s.lowest)}</dd></div>
            ${single ? '' : `<div><dt>Highest</dt><dd>${money(s.highest)}</dd></div>
            <div><dt>You save up to</dt><dd class="save">${money(s.spread)} <small>(${s.spreadPercent}%)</small></dd></div>`}
            ${s.averageRating !== undefined ? `<div><dt>Average rating</dt><dd>${stars(s.averageRating)} <small>${s.totalReviews.toLocaleString('en-IN')} reviews</small></dd></div>` : ''}
            <div><dt>Shops</dt><dd>${s.sites}</dd></div>
          </dl>
        </div>
      </div>
      ${c.warnings.length ? `<ul class="warnings">${c.warnings.map((w) => `<li>${esc(w)}</li>`).join('')}</ul>` : ''}
      ${single ? '<p class="muted">Only one shop has this product, so there is nothing to compare it with yet.</p>' : `
      <div class="sort">
        <label>Sort by
          <select class="sort-select">
            <option value="price">Lowest price</option>
            <option value="rating">Best rating</option>
            <option value="value">Best value</option>
          </select>
        </label>
      </div>`}
      <div class="table-wrap">
        <table>
          <thead><tr><th>Shop</th><th>Price</th><th>vs cheapest</th><th>Seller</th><th>Rating</th><th>Value</th><th></th></tr></thead>
          <tbody>${c.offers.map((o) => offerRow(o, c)).join('')}</tbody>
        </table>
      </div>
    </article>`;
}

function renderComparisons(container: HTMLElement, comparisons: Comparison[]) {
  container.insertAdjacentHTML('beforeend', comparisons.map(comparisonCard).join(''));
  container.querySelectorAll<HTMLElement>('article.product').forEach((card) => {
    const c = comparisons[Number(card.dataset.index)];
    card.querySelector<HTMLSelectElement>('.sort-select')?.addEventListener('change', (e) => {
      const key = (e.target as HTMLSelectElement).value as SortKey;
      card.querySelector('tbody')!.innerHTML = sortOffers(c.offers, key).map((o) => offerRow(o, c)).join('');
    });
  });
}

function renderErrors(errors: SourceError[], what: string): string {
  if (!errors.length) return '';
  return `<div class="card errors"><strong>${esc(what)}</strong><ul>${errors
    .map((e) => `<li><span class="err-source">${esc(e.source)}</span> ${esc(e.message)}</li>`)
    .join('')}</ul></div>`;
}

// ---- tabs ----------------------------------------------------------------------

function showTab(tab: 'search' | 'links') {
  for (const t of ['search', 'links'] as const) {
    $(`#tab-${t}`).setAttribute('aria-selected', String(t === tab));
    $(`#panel-${t}`).hidden = t !== tab;
  }
  const hash = tab === 'links' ? '#links' : '';
  if (location.hash !== hash) history.replaceState(null, '', hash || location.pathname + location.search);
}
$('#tab-search').addEventListener('click', () => showTab('search'));
$('#tab-links').addEventListener('click', () => showTab('links'));

// ---- search --------------------------------------------------------------------

const SUGGESTIONS = ['Galaxy S24', 'iPhone 15', 'Sony WH-1000XM5', 'boAt Airdopes', 'MacBook Air M3', 'Samsung 55 inch TV', 'Nike Revolution 7'];
$('#suggestions').innerHTML = SUGGESTIONS.map((s) => `<button type="button" class="chip">${esc(s)}</button>`).join('');
$('#suggestions').addEventListener('click', (e) => {
  const chip = (e.target as HTMLElement).closest('button');
  if (!chip) return;
  $<HTMLInputElement>('#q').value = chip.textContent ?? '';
  void runSearch(chip.textContent ?? '');
});

let searchSeq = 0;
async function runSearch(query: string) {
  const out = $('#search-results');
  const seq = ++searchSeq;
  const url = new URL(location.href);
  if (query) url.searchParams.set('q', query);
  else url.searchParams.delete('q');
  history.replaceState(null, '', url);
  out.innerHTML = '<p class="loading">Comparing shops…</p>';
  try {
    const r = await api<SearchResponse>(`/api/search?q=${encodeURIComponent(query)}`);
    if (seq !== searchSeq) return;
    out.innerHTML = '';
    if (r.sample) {
      out.insertAdjacentHTML(
        'beforeend',
        '<p class="notice">These are <strong>sample prices</strong> for trying the app, not live ones. For live prices, paste real product links under <a href="#links" data-tab="links">Compare my links</a>.</p>',
      );
    }
    out.insertAdjacentHTML('beforeend', renderErrors(r.errors, 'Some shops could not be searched'));
    if (!r.products.length) {
      out.insertAdjacentHTML('beforeend', `<p class="empty">No products found for “${esc(query)}”. Try fewer words.</p>`);
      return;
    }
    const multi = r.products.filter((p) => p.offers.length > 1).length;
    out.insertAdjacentHTML(
      'beforeend',
      `<p class="count">${r.products.length} product${r.products.length === 1 ? '' : 's'}${multi ? `, ${multi} sold by more than one shop` : ''}.</p>`,
    );
    renderComparisons(out, r.products);
  } catch (e) {
    if (seq === searchSeq) out.innerHTML = `<p class="error">${esc((e as Error).message)}</p>`;
  }
}

$('#search-form').addEventListener('submit', (e) => {
  e.preventDefault();
  void runSearch($<HTMLInputElement>('#q').value.trim());
});
document.addEventListener('click', (e) => {
  const a = (e.target as HTMLElement).closest<HTMLAnchorElement>('a[data-tab="links"]');
  if (a) {
    e.preventDefault();
    showTab('links');
    $<HTMLTextAreaElement>('#urls').focus();
  }
});

// ---- compare links -----------------------------------------------------------

const manual: Listing[] = [];

function renderManual() {
  $('#manual-list').innerHTML = manual
    .map(
      (m, i) => `<li><span><strong>${esc(m.siteName)}</strong> ${esc(formatMoney(m.price, m.currency))}${m.seller ? ` · ${esc(m.seller.name)}` : ''}</span>
        <button type="button" class="link" data-remove="${i}" aria-label="Remove ${esc(m.siteName)} offer">Remove</button></li>`,
    )
    .join('');
}

$('#add-manual').addEventListener('click', () => {
  const box = $('#manual');
  const field = (name: string) => $<HTMLInputElement>(`[name="${name}"]`, box);
  const num = (name: string) => (field(name).value === '' ? undefined : Number(field(name).value));
  const error = $('#links-error');
  const siteName = field('siteName').value.trim();
  const price = num('price');
  if (!siteName || !price || price <= 0) {
    error.textContent = 'An offer added by hand needs a shop name and a price.';
    return;
  }
  error.textContent = '';
  const sellerName = field('seller').value.trim();
  manual.push({
    site: siteName.toLowerCase(),
    siteName,
    title: field('title').value.trim() || 'Added by hand',
    url: field('url').value.trim(),
    price,
    shipping: num('shipping'),
    mrp: num('mrp'),
    currency: 'INR',
    seller: sellerName ? { name: sellerName, rating: num('sellerRating') } : undefined,
    rating: num('rating'),
    reviewCount: num('reviewCount'),
  });
  box.querySelectorAll('input').forEach((i) => (i.value = ''));
  renderManual();
});
$('#manual-list').addEventListener('click', (e) => {
  const btn = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-remove]');
  if (!btn) return;
  manual.splice(Number(btn.dataset.remove), 1);
  renderManual();
});

$('#links-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const error = $('#links-error');
  const out = $('#links-results');
  const button = $<HTMLButtonElement>('#links-form button[type="submit"]');
  const urls = $<HTMLTextAreaElement>('#urls').value.split(/\s+/).map((u) => u.trim()).filter(Boolean);
  error.textContent = '';
  if (!urls.length && !manual.length) {
    error.textContent = 'Paste at least one product link, or add an offer by hand.';
    return;
  }
  const bad = urls.find((u) => !/^https?:\/\/\S+\.\S+/i.test(u));
  if (bad) {
    error.textContent = `This does not look like a link: ${bad}`;
    return;
  }
  button.disabled = true;
  out.innerHTML = `<p class="loading">Reading ${urls.length} page${urls.length === 1 ? '' : 's'}…</p>`;
  try {
    const r = await api<CompareLinksResponse>('/api/compare-links', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ urls, manual }),
    });
    out.innerHTML = renderErrors(r.errors, 'Some links could not be read. You can add those offers by hand above.');
    if (r.comparison) renderComparisons(out, [r.comparison]);
    else if (!r.errors.length) out.insertAdjacentHTML('beforeend', '<p class="empty">Nothing to compare yet.</p>');
    if (r.errors.length) ($('#manual') as HTMLDetailsElement).open = true;
  } catch (err) {
    out.innerHTML = '';
    error.textContent = (err as Error).message;
  } finally {
    button.disabled = false;
  }
});

// ---- start ---------------------------------------------------------------------

const initial = new URL(location.href).searchParams.get('q') ?? '';
$<HTMLInputElement>('#q').value = initial;
if (location.hash === '#links') showTab('links');
void runSearch(initial);
