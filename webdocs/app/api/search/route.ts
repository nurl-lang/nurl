import { source } from '@/lib/source';
import { createFromSource } from 'fumadocs-core/search/server';

// Static export: the index is computed once at build time into a cached
// JSON file, and searched client-side (see components/search.tsx) instead
// of hitting a live server route.
export const revalidate = false;
export const { staticGET: GET } = createFromSource(source);
