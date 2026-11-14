// The Worker in front of nurl-lang.org's static export (out/). It runs only
// for the paths `assets.run_worker_first` in wrangler.jsonc lists — the
// homepage, the docs pages and the API catalog; every other request is
// served by the asset layer directly and costs no Worker invocation.
//
// - Markdown content negotiation: a request whose Accept prefers
//   text/markdown over text/html gets the page's Markdown twin
//   (/ → /index.md, /docs/<slug> → /llms.mdx/docs/<slug>/content.md).
//   `/docs/<slug>.md` serves the same Markdown to any client.
// - HTML answers carry `Vary: Accept` and a Link header to their Markdown
//   twin; the homepage also links the agent discovery documents (RFC 8288).
// - /.well-known/api-catalog is served as application/linkset+json
//   (RFC 9727), which a file without an extension cannot say by itself.

interface Env {
  ASSETS: { fetch(request: Request): Promise<Response> };
}

const HOME_LINKS = [
  '</.well-known/api-catalog>; rel="api-catalog"',
  '<https://play.nurl-lang.org/openapi.json>; rel="service-desc"; type="application/vnd.oai.openapi+json"',
  '</.well-known/mcp/server-card.json>; rel="describedby"; type="application/json"',
  '</.well-known/agent-skills/index.json>; rel="describedby"; type="application/json"',
  '</llms.txt>; rel="describedby"; type="text/plain"',
  '</docs>; rel="service-doc"; type="text/html"',
  '</index.md>; rel="alternate"; type="text/markdown"',
].join(', ');

const API_CATALOG_TYPE = 'application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727"';

/** The q-value the Accept header gives `type` (0 when absent). */
function quality(accept: string, types: string[]): number {
  let best = 0;
  for (const part of accept.split(',')) {
    const [media, ...params] = part.trim().split(';');
    if (!types.includes(media.trim().toLowerCase())) continue;
    let q = 1;
    for (const param of params) {
      const [key, value] = param.split('=');
      if (key.trim().toLowerCase() === 'q') q = Number.parseFloat(value) || 0;
    }
    best = Math.max(best, q);
  }
  return best;
}

function prefersMarkdown(request: Request): boolean {
  const accept = request.headers.get('Accept') ?? '';
  const md = quality(accept, ['text/markdown', 'text/x-markdown']);
  return md > 0 && md >= quality(accept, ['text/html', 'application/xhtml+xml']);
}

/** The Markdown asset for an HTML path, or null when it has none. */
function markdownAsset(htmlPath: string): string | null {
  const path = htmlPath.replace(/\/+$/, '') || '/';
  if (path === '/' || path === '/index') return '/index.md';
  if (path === '/docs') return '/llms.mdx/docs/content.md';
  if (path.startsWith('/docs/')) return `/llms.mdx${path}/content.md`;
  return null;
}

/** The public URL of an HTML path's Markdown twin. */
function markdownUrl(htmlPath: string): string | null {
  const path = htmlPath.replace(/\/+$/, '') || '/';
  if (path === '/') return '/index.md';
  if (path === '/docs' || path.startsWith('/docs/')) return `${path}.md`;
  return null;
}

function withHeaders(response: Response, headers: Record<string, string>, append: Record<string, string> = {}): Response {
  const out = new Response(response.body, response);
  for (const [name, value] of Object.entries(headers)) out.headers.set(name, value);
  for (const [name, value] of Object.entries(append)) out.headers.append(name, value);
  return out;
}

async function serveMarkdown(request: Request, env: Env, asset: string, canonical: string): Promise<Response | null> {
  const url = new URL(request.url);
  const res = await env.ASSETS.fetch(new Request(new URL(asset, url), { method: request.method, headers: request.headers }));
  if (!res.ok) return null;
  return withHeaders(res, {
    'Content-Type': 'text/markdown; charset=utf-8',
    Vary: 'Accept',
    Link: `<${canonical}>; rel="canonical"; type="text/html"`,
    'X-Robots-Tag': 'noindex',
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const readable = request.method === 'GET' || request.method === 'HEAD';

    if (path === '/.well-known/api-catalog') {
      const res = await env.ASSETS.fetch(request);
      return res.ok ? withHeaders(res, { 'Content-Type': API_CATALOG_TYPE }) : res;
    }

    if (readable) {
      // /docs/<slug>.md and /docs.md: the Markdown twin, whatever Accept says.
      if (path.endsWith('.md') && (path === '/docs.md' || path.startsWith('/docs/'))) {
        const html = path.slice(0, -'.md'.length);
        const asset = markdownAsset(html);
        const res = asset && (await serveMarkdown(request, env, asset, html));
        if (res) return res;
      } else if (prefersMarkdown(request)) {
        const asset = markdownAsset(path);
        const res = asset && (await serveMarkdown(request, env, asset, path));
        if (res) return res;
      }
    }

    const res = await env.ASSETS.fetch(request);
    const contentType = res.headers.get('Content-Type') ?? '';
    if (!contentType.startsWith('text/html')) return res;

    const md = res.ok ? markdownUrl(path) : null;
    const links = path === '/' ? HOME_LINKS : md ? `<${md}>; rel="alternate"; type="text/markdown"` : '';
    return withHeaders(res, { Vary: 'Accept' }, links ? { Link: links } : {});
  },
};
