import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { mcpUrl, siteUrl } from '@/lib/shared';
import { nurlVersion } from '@/lib/release-facts.generated';

// MCP Server Card (SEP-1649) for the hosted NURL MCP server, so an agent
// that only knows nurl-lang.org can find and connect to it. The version is
// the one the server reports in `initialize` (nurlapi/main.nu), read at
// build time; the toolchain version stands in if that line ever moves.
export const revalidate = false;

function serverVersion(): string {
  try {
    const src = readFileSync(join(process.cwd(), '..', 'nurlapi', 'main.nu'), 'utf8');
    const m = src.match(/NURL_MCP_SERVER_VERSION` `([^`]+)`/);
    if (m) return m[1];
  } catch {}
  return nurlVersion.replace(/^v/, '');
}

export function GET() {
  return Response.json({
    serverInfo: {
      name: 'nurl',
      title: 'NURL language toolchain',
      version: serverVersion(),
    },
    description:
      'Compile NURL source to Linux, Windows, macOS, WebAssembly, RISC-V/ARM64 and unikernel binaries, and read the NURL grammar, README, roadmap, changelog, docs, stdlib, examples and compiler tests. Public, no authentication.',
    url: mcpUrl,
    transport: { type: 'streamable-http' },
    capabilities: { tools: true, resources: true, prompts: true },
    authentication: { required: false },
    documentation: `${siteUrl}/docs/playground-ai`,
    websiteUrl: siteUrl,
    repository: 'https://github.com/nurl-lang/nurl',
  });
}
