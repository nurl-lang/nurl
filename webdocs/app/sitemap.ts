import type { MetadataRoute } from 'next';
import { source } from '@/lib/source';
import { siteUrl } from '@/lib/shared';

// Static export: written once at build time to out/sitemap.xml, which
// robots.txt points at. Lists the canonical HTML pages; each also has a
// Markdown twin (Accept: text/markdown, or the .md URL in /llms.txt).
export const dynamic = 'force-static';

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: `${siteUrl}/`, changeFrequency: 'weekly', priority: 1 },
    ...source.getPages().map((page) => ({
      url: `${siteUrl}${page.url}`,
      lastModified: page.data.lastModified,
      changeFrequency: 'weekly' as const,
      priority: page.slugs.length === 0 ? 0.9 : 0.7,
    })),
  ];
}
