// Agent-facing text: /llms.txt, the homepage's Markdown twin (/index.md),
// and the URLs both hand out. Every docs page has a Markdown twin at
// `<page url>.md` — and at its HTML URL for `Accept: text/markdown` — which
// worker/index.ts maps to the static export's /llms.mdx/docs/…/content.md.
import type { Node } from 'fumadocs-core/page-tree';
import { source } from './source';
import { benchmarkStats } from './benchmark-stats.generated';
import { nurlVersion, releaseFacts } from './release-facts.generated';
import { addExample, features, fizzBuzzExample, packages, projects, tagline } from './home-content';
import { mcpUrl, playgroundUrl, registryUrl, repoUrl, siteUrl } from './shared';
import targetFacts from '@/site-facts.json';

type Page = (typeof source)['$inferPage'];

export function markdownUrl(page: Page): string {
  return `${siteUrl}${page.url}.md`;
}

/** The docs as the sidebar shows them: `[section, pages][]` in order. */
function docsSections(): [string, Page[]][] {
  const byUrl = new Map(source.getPages().map((page) => [page.url, page]));
  const sections: [string, Page[]][] = [['Start here', []]];
  const walk = (nodes: Node[]) => {
    for (const node of nodes) {
      if (node.type === 'separator') sections.push([String(node.name ?? 'Docs'), []]);
      else if (node.type === 'page') {
        const page = byUrl.get(node.url);
        if (page) sections[sections.length - 1][1].push(page);
      } else if (node.type === 'folder') {
        if (node.index) {
          const page = byUrl.get(node.index.url);
          if (page) sections[sections.length - 1][1].push(page);
        }
        walk(node.children);
      }
    }
  };
  walk(source.getPageTree().children);
  return sections.filter(([, pages]) => pages.length > 0);
}

function pageLine(page: Page): string {
  const description = page.data.description?.trim();
  return `- [${page.data.title}](${markdownUrl(page)})${description ? `: ${description}` : ''}`;
}

const agentLinks = `- [MCP server](${mcpUrl}): build, cross-compile and read the grammar, stdlib, examples and docs over MCP (Streamable HTTP, no auth). Add it with \`claude mcp add --transport http nurl ${mcpUrl}\`. Card: ${siteUrl}/.well-known/mcp/server-card.json
- [Compiler HTTP API (OpenAPI 3.1)](${playgroundUrl}/openapi.json): the same build endpoints over plain HTTP; Swagger UI at ${playgroundUrl}/docs
- [Agent skill: writing NURL](${siteUrl}/.well-known/agent-skills/nurl/SKILL.md): how an agent should write, check and build NURL code
- [API catalog](${siteUrl}/.well-known/api-catalog): RFC 9727 linkset of the APIs above
- [Package registry](${registryUrl}): packages with generated API docs; JSON at ${registryUrl}/api/v1/catalog and ${registryUrl}/api/v1/search?q=…`;

/** /llms.txt — https://llmstxt.org/ */
export function llmsIndex(): string {
  const docs = docsSections()
    .map(([name, pages]) => `## ${name}\n\n${pages.map(pageLine).join('\n')}`)
    .join('\n\n');

  return `# NURL

> ${tagline}

NURL ${nurlVersion} is a self-hosting compiled language in prefix notation: \`@ add i a i b → i { ^ + a b }\` declares a function, \`( add 3 4 )\` calls it. Every link below is Markdown; every page of ${siteUrl} also answers \`Accept: text/markdown\`. All docs in one file: ${siteUrl}/llms-full.txt

${docs}

## Agent integrations

${agentLinks}

## Optional

- [Homepage](${siteUrl}/index.md): overview, benchmarks, targets, standard library
- [Source repository](${repoUrl}): compiler, stdlib, examples, spec/grammar.ebnf
- [Changelog](${repoUrl}/blob/main/CHANGELOG.md)
- [Roadmap](${repoUrl}/blob/main/ROADMAP.md)
`;
}

/** /index.md — the homepage (app/(home)/page.tsx) as Markdown. */
export function homeMarkdown(): string {
  const facts = releaseFacts.map(([value, label]) => `- **${value}** ${label}`).join('\n');
  const why = features.map(({ title, description }) => `- **${title}.** ${description}`).join('\n');
  const benchHeader = `| Benchmark | ${benchmarkStats.columns.join(' | ')} |\n|---|${benchmarkStats.columns.map(() => '---:').join('|')}|`;
  const benchRows = benchmarkStats.rows
    .map((row) => `| \`${row.name}\` — ${row.blurb} | ${row.values.join(' | ')} |`)
    .join('\n');
  const docs = docsSections()
    .map(([name, pages]) => `### ${name}\n\n${pages.map(pageLine).join('\n')}`)
    .join('\n\n');

  return `# NURL

${tagline}

Version ${nurlVersion} · [Docs](${siteUrl}/docs.md) · [Playground](${playgroundUrl}) · [GitHub](${repoUrl}) · [Package registry](${registryUrl})

${facts}

## Built for generated code

NURL keeps generated code easy to parse. Fixed arity removes precedence ambiguity, short dependency windows limit context, and the grammar fits on one page.

${why}

## Prefix notation, end to end

NURL uses \`OP ARG1 ARG2 …\`. There is no operator precedence or infix syntax.

Add two integers:

\`\`\`nurl
${addExample}
\`\`\`

FizzBuzz:

\`\`\`nurl
${fizzBuzzExample}
\`\`\`

See the [language reference](${siteUrl}/docs/cheat-sheet.md) for generics, traits, pattern matching, errors, channels, compile-time evaluation, and async runtime support.

## Measured runtime performance

${benchmarkStats.benchmarks} verified benchmarks compare NURL with C, Rust, Node, and Python; each implementation must produce the same output before timing. Median wall-clock time for the full process, lower is better — ${benchmarkStats.host}, measured ${benchmarkStats.generated}${benchmarkStats.runUrl ? ` ([CI run](${benchmarkStats.runUrl}))` : ''}. Sources: ${repoUrl}/tree/main/bench

${benchHeader}
${benchRows}

## Start with NURL

- **Try it in the browser:** ${playgroundUrl}
- **Install a release:** \`curl -fsSL ${siteUrl}/install.sh | sh\` (Linux, macOS) or \`irm ${siteUrl}/install.ps1 | iex\` (Windows). [Install guide](${siteUrl}/docs/install.md)
- **Build from source:** \`git clone ${repoUrl} && cd nurl && ./build.sh\`
- **Editor support:** the VS Code extension also works in Cursor and Windsurf, with diagnostics, completion, and formatting. [Editor guide](${siteUrl}/docs/editor-and-tooling.md)

## Targets

The compiler emits target-agnostic LLVM IR for desktop, server, browser, unikernel, and embedded targets: ${targetFacts.targets.join(', ')}.

## Standard library

${releaseFacts[2][0]} modules of plain NURL source, included with the toolchain: network (TCP, UDP, post-quantum TLS 1.3, QUIC, HTTP/1.1–3, WebSocket, MQTT, SMTP, peer-to-peer), data (JSON, Protobuf, Zstandard, TOML, YAML, XML, MessagePack, CBOR, CSV, PostgreSQL, SQLite), concurrency (threads, mutexes, channels, atomics, a stackful M:N async runtime), core (collections, arbitrary-precision numbers, regex, crypto, compression, UUIDs, paths, processes), AI and MCP (Anthropic API, MCP clients, servers, sessions, registries), and tooling (LSP, formatter, doc tools, test and benchmark runners, a differential fuzzer). [Browse the standard library](${siteUrl}/docs/standard-library.md)

## NURL projects

${projects.map(({ title, description, href }) => `- [${title}](${href}): ${description}`).join('\n')}

## Packages

The registry supports semver ranges, reproducible lockfiles, and signed tarballs verified by \`nurlpkg\` before unpacking: \`nurlpkg search whisper\`, \`nurlpkg install nq\`, \`nurlpkg add tensor\`, \`nurlpkg publish\`. Popular packages: ${packages.map((name) => `\`${name}\``).join(', ')}. ${registryUrl}

## For agents

${agentLinks}
- [llms.txt](${siteUrl}/llms.txt) · [llms-full.txt](${siteUrl}/llms-full.txt)

## Documentation

${docs}

---

Dual-licensed MIT / Apache-2.0.
`;
}
