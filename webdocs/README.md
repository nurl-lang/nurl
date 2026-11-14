# webdocs

NURL's web documentation site, built with [Fumadocs](https://fumadocs.dev)
(Next.js App Router). Generated with
[Create Fumadocs](https://github.com/fuma-nama/fumadocs).

Run development server:

```bash
npm run dev
# or
pnpm dev
# or
yarn dev
```

Open http://localhost:3000 with your browser to see the result.

## Explore

In the project, you can see:

- `lib/source.ts`: Code for content source adapter, [`loader()`](https://fumadocs.dev/docs/headless/source-api) provides the interface to access your content.
- `lib/layout.shared.tsx`: Shared options for layouts, optional but preferred to keep.

| Route                     | Description                                            |
| ------------------------- | ------------------------------------------------------ |
| `app/(home)`              | The route group for your landing page and other pages. |
| `app/docs`                | The documentation layout and pages.                    |
| `app/api/search/route.ts` | The Route Handler for search.                          |

## For agents

nurl-lang.org is built to be read by AI agents as well as people (Cloudflare's
Agent Readiness checks, https://isitagentready.com):

| URL | Source | What |
| --- | --- | --- |
| `/robots.txt` | `public/robots.txt` | Every crawler allowed; `Content-Signal` search, ai-input and ai-train all `yes`; points at the sitemap |
| `/sitemap.xml` | `app/sitemap.ts` | The homepage and every docs page |
| `/llms.txt`, `/llms-full.txt` | `app/llms*.txt`, `lib/agents.ts` | The docs index (Markdown links) and every page in one file |
| `Accept: text/markdown`, `/docs/<page>.md` | `worker/index.ts` | Every page's Markdown twin; `/` → `/index.md` (`app/index.md`, `lib/agents.ts`) |
| `/.well-known/api-catalog` | `app/.well-known/api-catalog` | RFC 9727 catalog of the playground API, the MCP server and the registry API |
| `/.well-known/mcp/server-card.json` | `app/.well-known/mcp/…` | MCP Server Card for `https://play.nurl-lang.org/mcp` |
| `/.well-known/agent-skills/index.json` | `app/.well-known/agent-skills/…` | Agent Skills index; the skill itself is `public/.well-known/agent-skills/nurl/SKILL.md` (digest computed at build) |

The Worker (`worker/index.ts`) runs only for the paths in `wrangler.jsonc`'s
`assets.run_worker_first`; everything else is served straight from the
static export. To try it locally: `pnpm build && npx wrangler dev`, then
`curl -H 'Accept: text/markdown' localhost:8787/`.

### Fumadocs MDX

A `source.config.ts` config file has been included, you can customise different options like frontmatter schema.

Read the [Introduction](https://fumadocs.dev/docs/mdx) for further details.

## Learn More

To learn more about Next.js and Fumadocs, take a look at the following
resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js
  features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.
- [Fumadocs](https://fumadocs.dev) - learn about Fumadocs
