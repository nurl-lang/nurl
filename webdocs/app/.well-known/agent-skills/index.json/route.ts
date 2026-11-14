import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Agent Skills discovery index (v0.2.0,
// https://github.com/cloudflare/agent-skills-discovery-rfc). Each skill is
// a SKILL.md under public/.well-known/agent-skills/<name>/; its digest is
// computed here at build time, so editing the file can never leave a stale
// digest behind.
export const revalidate = false;

const skills = [
  {
    name: 'nurl',
    description:
      'Write, check and build programs in NURL, a compiled prefix-notation language (.nu files) that lowers to LLVM IR. Use when a task asks for NURL code, touches .nu files, or needs a NURL program built for Linux, Windows, macOS, WebAssembly, RISC-V/ARM64 or a unikernel.',
  },
];

export function GET() {
  return Response.json({
    $schema: 'https://schemas.agentskills.io/discovery/0.2.0/schema.json',
    skills: skills.map(({ name, description }) => {
      const url = `/.well-known/agent-skills/${name}/SKILL.md`;
      const bytes = readFileSync(join(process.cwd(), 'public', url));
      return {
        name,
        type: 'skill-md',
        description,
        url,
        digest: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      };
    }),
  });
}
