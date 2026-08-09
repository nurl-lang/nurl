// artifacts.ts — pure policy for persisting build artifacts in R2.
//
// The container writes every build's outputs under <output_dir>/<build_id>/
// on its own disk and hands out /download/<build_id>/<name> URLs. That disk
// is ephemeral: the instance recycles on idle (sleepAfter), on deploy-stamp
// mismatch, and on wedge recovery — and every recycle silently invalidates
// every previously issued download URL. The Worker therefore mirrors
// artifacts to R2 (keyed by their token) as they are produced and serves
// downloads R2-first, so a URL keeps working across container generations.
//
// This module is cloudflare-import-free so it can be unit-tested under Node
// (npm run test:artifacts), same as ./recovery.

// A token is "<build_id>/<name>". Both segments are generated server-side
// (build ids are timestamps, names derive from sanitized program names), so
// a conservative charset loses nothing — and guarantees a token can never
// traverse out of the bucket namespace or smuggle a sub-path.
const SEGMENT_RE = /^[A-Za-z0-9_.-]{1,128}$/;

export function isSafeToken(token: string): boolean {
  const parts = token.split("/");
  if (parts.length !== 2) return false;
  // `.`/`..` pass the charset test but are path segments, not names.
  return parts.every((p) => SEGMENT_RE.test(p) && !/^\.+$/.test(p));
}

// R2 key for a request path, or null when the path is not a well-formed
// artifact download (null = just proxy it; the container owns the answer).
export function downloadKey(pathname: string): string | null {
  if (!pathname.startsWith("/download/")) return null;
  const token = pathname.slice("/download/".length);
  return isSafeToken(token) ? token : null;
}

// Scan a build response body for the artifacts it references. Works on both
// shapes that mention them: the REST /build* JSON (ll_artifact /
// binary_artifact / wasm_artifact objects with download_url + token) and the
// MCP tool-call result, where the same URLs sit inside JSON-encoded text —
// a URL substring match covers both without modelling either schema.
// Capped so a hostile body can't fan out unbounded mirror traffic.
export const MAX_TOKENS_PER_RESPONSE = 16;

const TOKEN_RE = /\/download\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)/g;

export function extractArtifactTokens(text: string): string[] {
  const seen = new Set<string>();
  for (const m of text.matchAll(TOKEN_RE)) {
    const token = m[1];
    if (!isSafeToken(token)) continue;
    seen.add(token);
    if (seen.size >= MAX_TOKENS_PER_RESPONSE) break;
  }
  return [...seen];
}

// Should this request's response be scanned for artifact tokens? Builds
// arrive as POST /build* (REST) or POST /mcp (tool calls).
export function shouldScanForArtifacts(method: string, pathname: string): boolean {
  if (method !== "POST") return false;
  return pathname.startsWith("/build") || pathname === "/mcp";
}
