import { mcpUrl, playgroundUrl, registryUrl, siteUrl } from '@/lib/shared';

// API catalog (RFC 9727): a linkset (RFC 9264) of the NURL project's APIs.
// worker/index.ts serves it as application/linkset+json; the static export
// writes it as a plain file.
export const revalidate = false;

export function GET() {
  return Response.json({
    linkset: [
      {
        anchor: `${siteUrl}/.well-known/api-catalog`,
        item: [{ href: `${playgroundUrl}/` }, { href: mcpUrl }, { href: `${registryUrl}/api/v1/` }],
      },
      {
        anchor: `${playgroundUrl}/`,
        'service-desc': [{ href: `${playgroundUrl}/openapi.json`, type: 'application/vnd.oai.openapi+json;version=3.1' }],
        'service-doc': [
          { href: `${playgroundUrl}/docs`, type: 'text/html' },
          { href: `${siteUrl}/docs/playground-ai.md`, type: 'text/markdown' },
        ],
        status: [{ href: `${playgroundUrl}/health`, type: 'application/json' }],
      },
      {
        anchor: mcpUrl,
        'service-desc': [{ href: `${siteUrl}/.well-known/mcp/server-card.json`, type: 'application/json' }],
        'service-doc': [{ href: `${siteUrl}/docs/playground-ai.md`, type: 'text/markdown' }],
        status: [{ href: `${playgroundUrl}/health`, type: 'application/json' }],
      },
      {
        anchor: `${registryUrl}/api/v1/`,
        'service-doc': [{ href: `${registryUrl}/`, type: 'text/html' }],
        status: [{ href: `${registryUrl}/api/v1/stats`, type: 'application/json' }],
      },
    ],
  });
}
