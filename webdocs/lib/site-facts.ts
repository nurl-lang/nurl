import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Computed once at build time (this is a static export — see next.config.mjs).
// Mirrors the resolution order in ../tools/gen-site-facts.sh / version.sh so
// the docs site stays consistent with nurlweb: CHANGELOG.md's newest released
// section is the source of truth for the language version (it lands in the
// same PR as a release, before the `v*` tag is cut), falling back to git tags.

function repoRoot(): string {
  try {
    return execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
  } catch {
    // No git available (e.g. a source tarball) — webdocs/ sits one level
    // below the repo root on disk.
    return join(process.cwd(), '..');
  }
}

function resolveNurlVersion(root: string): string {
  try {
    const changelog = readFileSync(join(root, 'CHANGELOG.md'), 'utf8');
    const match = changelog.match(/^## \[(\d+\.\d+\.\d+)\]/m);
    if (match) return `v${match[1]}`;
  } catch {
    // CHANGELOG.md not readable; fall through to git tags.
  }
  try {
    const tags = execSync('git tag --sort=-version:refname', { cwd: root, encoding: 'utf8' });
    const tag = tags.split('\n').find((t) => /^v\d/.test(t));
    if (tag) return tag;
  } catch {
    // No tags reachable either.
  }
  return 'v0.0.0';
}

function resolveDocsCommit(root: string): string {
  try {
    return execSync('git rev-parse --short HEAD', { cwd: root, encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

const root = repoRoot();

export const siteFacts = {
  nurlVersion: resolveNurlVersion(root),
  docsCommit: resolveDocsCommit(root),
};
