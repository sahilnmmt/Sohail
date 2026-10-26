import type { Source } from './source.ts';
import { sampleSource } from './sample.ts';

/**
 * The sources searched for every query. Add live sources here, for example an
 * adapter for the Amazon Product Advertising API or the Flipkart Affiliate API,
 * once you have keys for them. Set PRICECOMPARE_SAMPLE=0 to hide the sample
 * catalogue.
 */
export function enabledSources(env = process.env): Source[] {
  const sources: Source[] = [];
  if (env.PRICECOMPARE_SAMPLE !== '0') sources.push(sampleSource);
  return sources;
}
