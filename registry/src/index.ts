// registry/src/index.ts — NURL package registry (Cloudflare Worker).
//
// Read path (static, cacheable):
//   GET  /index/<name>.json            → R2 object index/<name>.json
//   GET  /pkgs/<name>/<file>.tar.gz    → R2 object pkgs/<name>/<file>.tar.gz
//
// Write path (authenticated):
//   POST /api/v1/publish               → Bearer token; X-Nurl-Package /
//        X-Nurl-Version headers; body = .tar.gz. The server recomputes the
//        SHA-256 (never trusts a client digest), enforces first-publisher
//        name ownership + version immutability, writes the tarball + the
//        updated index to R2, and records the version in D1.
//
// Auth bootstrap (GitHub OAuth):
//   GET  /login                        → redirect to GitHub authorize
//   GET  /auth/callback?code=...       → exchange, upsert user, mint a
//        registry token (shown once; only its peppered SHA-256 is stored)
//
// This implements exactly the wire contract the NURL client already drives
// (see stdlib/ext/pkg_fetch.nu + pkg_publish.nu and the round-trip proven
// against a static python registry). It runs locally under `wrangler dev`
// (miniflare simulates R2 + D1) — no Cloudflare account needed to test.

import { renderMarkdown } from "./markdown.ts";
import { extractReadme, extractFile, extractManifestRepository, normalizeRelPath } from "./readme.ts";

export interface Env {
  REG_BUCKET: R2Bucket;
  REG_DB: D1Database;
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string; // wrangler secret
  TOKEN_PEPPER: string;         // wrangler secret
  REGISTRY_URL: string;         // public base, e.g. https://reg.nurl-lang.org
  REG_SIGN_KEY?: string;        // wrangler secret: base64 Ed25519 seed (32B) —
                                // signs every published tarball (minisign legacy
                                // 'Ed' mode). Unset ⇒ publishes stay unsigned.
}

const NAME_RE = /^[a-z0-9](?:[a-z0-9_-]{0,63})$/;
const VERSION_RE = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)*$/;

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...extra },
  });
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(data: ArrayBuffer | string): Promise<string> {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data;
  return toHex(await crypto.subtle.digest("SHA-256", buf));
}

// ── Package signing (minisign legacy 'Ed' mode) ──────────────────────
// The registry holds a project Ed25519 key and signs every tarball with it.
// nurlpkg pins the matching public key and verifies with its pure-NURL
// minisign implementation, so a compromised R2/CDN can't swap in bad bytes.
//
// We use minisign's LEGACY signature (algorithm 'Ed'): a raw Ed25519
// signature over the tarball bytes — no BLAKE2b prehash — because Web Crypto
// exposes Ed25519 but not BLAKE2b. The pure-NURL verifier supports both.

// keyid = first 8 bytes of the .minisig, must match the pinned public key's.
// Public key: RWTGgah04Ft7n6+UNxc/MKT4eMViHBo4DLgKryJVbv9ZwedeQWpmmPq5
const REG_SIGN_KEYID = new Uint8Array([0xc6, 0x81, 0xa8, 0x74, 0xe0, 0x5b, 0x7b, 0x9f]);

// PKCS#8 wrapper for a bare Ed25519 seed: SEQUENCE header + OID + the 32-byte
// seed as an OCTET STRING. Lets crypto.subtle.importKey ingest a raw seed.
const PKCS8_ED25519_PREFIX = new Uint8Array([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
  0x04, 0x22, 0x04, 0x20,
]);

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

// Produce the .minisig text signing `body` with the given base64 Ed25519 seed.
async function signTarball(seedB64: string, body: ArrayBuffer): Promise<string> {
  const seed = b64ToBytes(seedB64);
  if (seed.length !== 32) throw new Error("REG_SIGN_KEY must be a 32-byte Ed25519 seed");
  const pkcs8 = new Uint8Array(PKCS8_ED25519_PREFIX.length + 32);
  pkcs8.set(PKCS8_ED25519_PREFIX);
  pkcs8.set(seed, PKCS8_ED25519_PREFIX.length);
  const key = await crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("Ed25519", key, body)); // raw msg
  // signature line 2 = base64( 'Ed' | keyid(8) | sig(64) )
  const line = new Uint8Array(2 + 8 + 64);
  line[0] = 0x45; // 'E'
  line[1] = 0x64; // 'd'  → legacy raw-Ed25519 mode
  line.set(REG_SIGN_KEYID, 2);
  line.set(sig, 10);
  return `untrusted comment: nurl registry signature\n${bytesToB64(line)}\n`;
}

// token_hash = sha256(pepper || token), hex. The pepper is a Worker secret
// so a D1 dump alone can't be brute-forced into live tokens.
function hashToken(token: string, pepper: string): Promise<string> {
  return sha256Hex(pepper + token);
}

function randomToken(): string {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

interface UserRow { id: number; github_id: number; login: string; }

// Resolve the Bearer token to a user, or null. Bumps last_used_at.
async function userFromAuth(req: Request, env: Env): Promise<UserRow | null> {
  const auth = req.headers.get("authorization") ?? "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const hash = await hashToken(m[1].trim(), env.TOKEN_PEPPER);
  const row = await env.REG_DB.prepare(
    `SELECT u.id AS id, u.github_id AS github_id, u.login AS login, t.id AS tid
       FROM tokens t JOIN users u ON u.id = t.user_id
      WHERE t.token_hash = ?`,
  ).bind(hash).first<UserRow & { tid: number }>();
  if (!row) return null;
  await env.REG_DB.prepare(`UPDATE tokens SET last_used_at = ? WHERE id = ?`)
    .bind(Date.now(), row.tid).run();
  return { id: row.id, github_id: row.github_id, login: row.login };
}

interface IndexDep { name: string; req: string; }
interface IndexVersion { version: string; checksum: string; yanked: boolean; deps: IndexDep[]; }
interface PackageIndex { name: string; versions: IndexVersion[]; }

async function readIndex(env: Env, name: string): Promise<PackageIndex> {
  const obj = await env.REG_BUCKET.get(`index/${name}.json`);
  if (!obj) return { name, versions: [] };
  return JSON.parse(await obj.text()) as PackageIndex;
}

// Optional X-Nurl-Deps: JSON array of { name, req }. Lets transitive
// registry resolution work; defaults to [] when the client omits it.
function parseDeps(req: Request): IndexDep[] {
  const raw = req.headers.get("x-nurl-deps");
  if (!raw) return [];
  try {
    const arr = JSON.parse(raw);
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((d) => d && typeof d.name === "string" && typeof d.req === "string")
      .map((d) => ({ name: d.name, req: d.req }));
  } catch {
    return [];
  }
}

async function serveR2(env: Env, key: string, contentType: string): Promise<Response> {
  const obj = await env.REG_BUCKET.get(key);
  if (!obj) return json({ error: "not_found" }, 404);
  const headers = new Headers();
  headers.set("content-type", contentType);
  headers.set("etag", obj.httpEtag);
  // Tarballs are content-addressed + immutable; index is small + mutable.
  headers.set("cache-control", key.startsWith("pkgs/") ? "public, max-age=31536000, immutable" : "public, max-age=60");
  return new Response(obj.body, { headers });
}

// Image MIME types we serve from package tarballs (README assets). Limiting
// to images keeps the asset route from doubling as a general file host.
const ASSET_MIME: Record<string, string> = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  webp: "image/webp", svg: "image/svg+xml", ico: "image/x-icon",
  bmp: "image/bmp", avif: "image/avif",
};

// GET /files/<name>/<version>/<relpath> — extract a README-referenced image
// straight from the published tarball. Version-pinned, so immutable-cacheable.
async function handleFile(env: Env, name: string, version: string, rel: string): Promise<Response> {
  if (!NAME_RE.test(name) || !VERSION_RE.test(version)) return json({ error: "bad_path" }, 400);
  const safe = normalizeRelPath(rel);
  if (!safe) return json({ error: "bad_path" }, 400);
  const ext = safe.includes(".") ? safe.split(".").pop()!.toLowerCase() : "";
  const mime = ASSET_MIME[ext];
  if (!mime) return json({ error: "unsupported_type" }, 415);
  let data: Uint8Array | null = null;
  try { data = await extractFile(env.REG_BUCKET, name, version, safe); }
  catch { return json({ error: "extract_failed" }, 500); }
  if (!data) return json({ error: "not_found" }, 404);
  const headers = new Headers();
  headers.set("content-type", mime);
  headers.set("cache-control", "public, max-age=31536000, immutable");
  headers.set("x-content-type-options", "nosniff");
  // Neutralise any script an SVG might carry, even on direct navigation.
  headers.set("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox");
  return new Response(data, { headers });
}

async function handlePublish(req: Request, env: Env): Promise<Response> {
  const user = await userFromAuth(req, env);
  if (!user) return json({ error: "unauthorized" }, 401);

  const name = (req.headers.get("x-nurl-package") ?? "").toLowerCase();
  const version = req.headers.get("x-nurl-version") ?? "";
  if (!NAME_RE.test(name)) return json({ error: "invalid_name" }, 400);
  if (!VERSION_RE.test(version)) return json({ error: "invalid_version" }, 400);

  const body = await req.arrayBuffer();
  if (body.byteLength === 0) return json({ error: "empty_body" }, 400);
  if (body.byteLength > 16 * 1024 * 1024) return json({ error: "too_large" }, 413);
  const checksum = await sha256Hex(body);

  // First-publisher ownership.
  const owner = await env.REG_DB.prepare(`SELECT owner_user_id FROM packages WHERE name = ?`)
    .bind(name).first<{ owner_user_id: number }>();
  if (owner && owner.owner_user_id !== user.id) return json({ error: "not_owner" }, 403);

  // Immutability.
  const existing = await env.REG_DB.prepare(`SELECT version FROM versions WHERE name = ? AND version = ?`)
    .bind(name, version).first();
  if (existing) return json({ error: "version_exists" }, 409);

  // Sign the tarball before storing it, so the signature lands atomically with
  // the bytes. A signing failure ABORTS the publish — we never expose an
  // unsigned tarball once a key is configured (fail-closed).
  const tarKey = `pkgs/${name}/${name}-${version}.tar.gz`;
  await env.REG_BUCKET.put(tarKey, body);
  if (env.REG_SIGN_KEY) {
    try {
      const sig = await signTarball(env.REG_SIGN_KEY, body);
      await env.REG_BUCKET.put(`${tarKey}.minisig`, sig, {
        httpMetadata: { contentType: "text/plain" },
      });
    } catch (e) {
      await env.REG_BUCKET.delete(tarKey); // don't leave signed-expecting bytes unsigned
      return json({ error: "signing_failed", detail: String(e) }, 500);
    }
  }
  const idx = await readIndex(env, name);
  idx.versions.push({ version, checksum, yanked: false, deps: parseDeps(req) });
  await env.REG_BUCKET.put(`index/${name}.json`, JSON.stringify(idx));

  const now = Date.now();
  if (!owner) {
    await env.REG_DB.prepare(`INSERT INTO packages (name, owner_user_id, created_at) VALUES (?, ?, ?)`)
      .bind(name, user.id, now).run();
  }
  await env.REG_DB.prepare(
    `INSERT INTO versions (name, version, checksum, yanked, published_by, published_at)
     VALUES (?, ?, ?, 0, ?, ?)`,
  ).bind(name, version, checksum, user.id, now).run();

  return json({ ok: true, name, version, checksum });
}

// Constant-time string compare (avoid leaking the admin key via timing).
function ctEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// POST /api/v1/admin/sign-backfill — sign every already-published tarball that
// lacks a .minisig, using the registry key. Idempotent: re-running only signs
// what's still missing. Gated on presenting the REG_SIGN_KEY seed itself
// (X-Reg-Sign-Key), so only the key holder can trigger it. This is the
// one-time migration that lets nurlpkg make signature checks MANDATORY without
// stranding packages published before signing existed.
async function handleSignBackfill(req: Request, env: Env): Promise<Response> {
  if (!env.REG_SIGN_KEY) return json({ error: "signing_not_configured" }, 503);
  const presented = req.headers.get("x-reg-sign-key") ?? "";
  if (!ctEq(presented, env.REG_SIGN_KEY)) return json({ error: "unauthorized" }, 401);

  // Enumerate everything under pkgs/ (paginated), then sign each .tar.gz whose
  // .minisig sibling is absent.
  const keys = new Set<string>();
  let cursor: string | undefined;
  do {
    const page = await env.REG_BUCKET.list({ prefix: "pkgs/", cursor, limit: 1000 });
    for (const o of page.objects) keys.add(o.key);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);

  let signed = 0, skipped = 0, failed = 0;
  const errors: string[] = [];
  for (const key of keys) {
    if (!key.endsWith(".tar.gz")) continue;
    if (keys.has(`${key}.minisig`)) { skipped++; continue; }
    try {
      const obj = await env.REG_BUCKET.get(key);
      if (!obj) { failed++; errors.push(`${key}: vanished`); continue; }
      const body = await obj.arrayBuffer();
      const sig = await signTarball(env.REG_SIGN_KEY, body);
      await env.REG_BUCKET.put(`${key}.minisig`, sig, { httpMetadata: { contentType: "text/plain" } });
      signed++;
    } catch (e) {
      failed++;
      errors.push(`${key}: ${String(e)}`);
    }
  }
  return json({ ok: failed === 0, signed, skipped, failed, errors });
}

// ── GitHub OAuth (token bootstrap) ────────────────────────────────────

const PAGE_STYLE =
  `body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:48rem;` +
    `margin:3rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}` +
  `a{color:#0b62d6}` +
  `h1{margin-bottom:.2em}` +
  `code{background:#f4f4f4;padding:.1em .35em;border-radius:4px;font-size:.92em}` +
  `pre{background:#f4f4f4;padding:1rem;border-radius:6px;overflow:auto}` +
  `pre code{background:transparent;padding:0}` +
  `.readme{border-top:1px solid #e5e5e5;margin-top:2.5rem;padding-top:.5rem}` +
  `.readme img{max-width:100%}` +
  `.readme table{border-collapse:collapse;margin:1rem 0}` +
  `.readme th,.readme td{border:1px solid #ddd;padding:.4rem .7rem;text-align:left}` +
  `.readme th{background:#f4f4f4}` +
  `.readme blockquote{border-left:3px solid #ddd;margin:1em 0;padding:.2rem 1rem;color:#555}` +
  `.readme h1,.readme h2{border-bottom:1px solid #eee;padding-bottom:.2em}` +
  `.readme hr{border:0;border-top:1px solid #e5e5e5;margin:2rem 0}` +
  `.site-head{display:flex;align-items:center;gap:.6rem;` +
    `margin:-1rem 0 1.8rem;padding-bottom:1rem;border-bottom:1px solid #e5e5e5}` +
  `.site-head .brand{display:flex;align-items:center;gap:.6rem;text-decoration:none;color:#1a1a1a}` +
  `.site-head .badge{display:inline-flex;background:#0f1115;border-radius:9px;padding:5px;` +
    `box-shadow:0 2px 10px rgba(20,184,166,.25)}` +
  `.site-head .badge img{display:block}` +
  `.site-head .wm{font-size:1.1rem;font-weight:600;letter-spacing:.01em}` +
  `.site-head .wm b{color:#0b62d6}` +
  `.site-head .spacer{flex:1}` +
  `.site-head .home{font-size:.85rem;color:#666;font-weight:400;text-decoration:none;transition:color .15s}` +
  `.site-head .home:hover{color:#0b62d6}`;

// Branded header injected on every registry page. The mark is served from
// the main site (nurl-lang.org) and sits on a dark chip so the neon reads
// against the light page.
const SITE_HEAD =
  `<div class="site-head">` +
    `<a class="brand" href="/">` +
      `<span class="badge"><img src="https://nurl-lang.org/img/logo-sm.png" width="30" height="30" alt="NURL"></span>` +
      `<span class="wm">NURL <b>registry</b></span>` +
    `</a>` +
    `<span class="spacer"></span>` +
    `<a class="home" href="https://nurl-lang.org/" target="_blank" rel="noopener">nurl-lang.org →</a>` +
  `</div>`;

function htmlPage(title: string, bodyHtml: string, status = 200): Response {
  return new Response(
    `<!doctype html><meta charset=utf-8><title>${title}</title>` +
      `<meta name=viewport content="width=device-width,initial-scale=1">` +
      `<link rel="icon" href="https://nurl-lang.org/favicon.svg">` +
      `<style>${PAGE_STYLE}</style>` +
      `<body>${SITE_HEAD}${bodyHtml}</body>`,
    { status, headers: { "content-type": "text/html; charset=utf-8" } },
  );
}

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

// ── Catalog UI + search ───────────────────────────────────────────────

interface CatalogRow { name: string; latest: string | null; }

// Most-recently-published non-yanked version per package (display only).
const LATEST_SUBQUERY =
  `(SELECT v.version FROM versions v WHERE v.name = p.name AND v.yanked = 0
      ORDER BY v.published_at DESC LIMIT 1)`;

async function handleCatalog(url: URL, env: Env): Promise<Response> {
  const q = (url.searchParams.get("q") ?? "").toLowerCase().slice(0, 64);
  const like = q ? `%${q.replace(/[%_\\]/g, "")}%` : "%";
  const rows = await env.REG_DB.prepare(
    `SELECT p.name AS name, ${LATEST_SUBQUERY} AS latest
       FROM packages p WHERE p.name LIKE ? ORDER BY p.name LIMIT 200`,
  ).bind(like).all<CatalogRow>();
  const items = rows.results ?? [];
  const list = items.length
    ? `<ul>${items.map((p) =>
        `<li><a href="/packages/${esc(p.name)}">${esc(p.name)}</a> ` +
        (p.latest ? `<code>${esc(p.latest)}</code>` : `<em>(all versions yanked)</em>`) + `</li>`).join("")}</ul>`
    : `<p>No packages${q ? ` matching “${esc(q)}”` : " published"} yet.</p>`;
  return htmlPage("NURL registry",
    `<h1>Packages</h1>` +
    `<form method=get><input name=q value="${esc(q)}" placeholder="search packages" ` +
      `style="padding:.4rem;width:60%"> <button>Search</button></form>` +
    `<p style="color:#666">${items.length} package(s) · <a href="/login">get a publish token →</a></p>` +
    list);
}

async function handlePackageDetail(env: Env, name: string): Promise<Response> {
  if (!NAME_RE.test(name)) return htmlPage("not found", `<p>Invalid package name.</p>`, 404);
  const idx = await readIndex(env, name);
  if (idx.versions.length === 0) {
    return htmlPage("not found", `<p><a href="/">← all packages</a></p><h1>${esc(name)}</h1><p>Not found.</p>`, 404);
  }
  const newestFirst = [...idx.versions].reverse();
  const latest = newestFirst.find((v) => !v.yanked);

  // Verified authorship, straight from the D1 identity tables (not any
  // self-declared manifest field): the package owner (first publisher) and
  // the GitHub login that published each version.
  const ownerRow = await env.REG_DB.prepare(
    `SELECT u.login AS login
       FROM packages p JOIN users u ON u.id = p.owner_user_id
      WHERE p.name = ?`,
  ).bind(name).first<{ login: string }>();
  const pubRows = await env.REG_DB.prepare(
    `SELECT v.version AS version, u.login AS login
       FROM versions v JOIN users u ON u.id = v.published_by
      WHERE v.name = ?`,
  ).bind(name).all<{ version: string; login: string }>();
  const pubBy = new Map((pubRows.results ?? []).map((r) => [r.version, r.login]));
  const ghLink = (login: string) =>
    `<a href="https://github.com/${esc(login)}">@${esc(login)}</a>`;
  const ownerHtml = ownerRow
    ? `<p style="color:#666">owner ${ghLink(ownerRow.login)}</p>`
    : "";

  const versionsHtml = newestFirst.map((v) => {
    const pub = pubBy.get(v.version);
    return `<li><code>${esc(v.version)}</code>` +
      (v.yanked ? ` <span style="color:#b00">(yanked)</span>` : "") +
      (pub ? ` <span style="color:#999">· ${ghLink(pub)}</span>` : "") +
      `</li>`;
  }).join("");
  const depsHtml = latest && latest.deps.length
    ? `<ul>${latest.deps.map((d) =>
        `<li><a href="/packages/${esc(d.name)}">${esc(d.name)}</a> <code>${esc(d.req)}</code></li>`).join("")}</ul>`
    : `<p>None.</p>`;
  const reqStr = latest ? `^${latest.version}` : "*";

  // Repository link, read straight from the latest tarball's nurl.toml
  // ([package].repository). Only http(s) URLs are rendered as links.
  let repoHtml = "";
  if (latest) {
    try {
      const repo = await extractManifestRepository(env.REG_BUCKET, name, latest.version);
      if (repo && /^https?:\/\//i.test(repo)) {
        repoHtml = `<p style="color:#666">repository <a href="${esc(repo)}">${esc(repo)}</a></p>`;
      }
    } catch { /* no repository line */ }
  }

  // README of the latest published version, rendered from its tarball.
  // Never let a missing/odd archive break the page.
  let readmeHtml = "";
  if (latest) {
    try {
      const md = await extractReadme(env.REG_BUCKET, name, latest.version);
      if (md && md.length <= 512 * 1024) {
        // Point the README's relative targets (e.g. `docs/demo.png`) at the
        // tarball-asset route so embedded images resolve; leave absolute /
        // scheme / fragment URLs untouched.
        const base = `/files/${name}/${latest.version}/`;
        const resolve = (u: string): string => {
          if (/^[a-z][a-z0-9+.-]*:/i.test(u) || u.startsWith("/") || u.startsWith("#")) return u;
          // A monorepo sibling-package reference (`../onnx`, common in these
          // READMEs) maps to that package's page, not a file in the tarball.
          const sib = u.match(/^\.\.\/([a-z0-9][a-z0-9_-]*)\/?$/i);
          if (sib) return `/packages/${sib[1].toLowerCase()}`;
          const norm = normalizeRelPath(u);
          return norm ? base + norm : u;
        };
        readmeHtml = `<div class="readme">${renderMarkdown(md, resolve)}</div>`;
      }
    } catch { /* fall through with no README */ }
  }

  return htmlPage(name,
    `<p><a href="/">← all packages</a></p><h1>${esc(name)}</h1>` +
    ownerHtml +
    repoHtml +
    `<h3>Install</h3><pre>[dependencies]\n${esc(name)} = "${esc(reqStr)}"</pre>` +
    `<h3>Versions</h3><ul>${versionsHtml}</ul>` +
    `<h3>Dependencies (latest)</h3>${depsHtml}` +
    readmeHtml);
}

async function handleSearch(url: URL, env: Env): Promise<Response> {
  const q = (url.searchParams.get("q") ?? "").toLowerCase().slice(0, 64);
  const like = q ? `%${q.replace(/[%_\\]/g, "")}%` : "%";
  const rows = await env.REG_DB.prepare(
    `SELECT p.name AS name, ${LATEST_SUBQUERY} AS latest
       FROM packages p WHERE p.name LIKE ? ORDER BY p.name LIMIT 50`,
  ).bind(like).all<CatalogRow>();
  return json({ results: (rows.results ?? []).map((r) => ({ name: r.name, version: r.latest })) });
}

// Public counts — powers the "registry packages" figure on nurl-lang.org
// (injected at build time by tools/gen-site-facts.sh). CORS-open and briefly
// cached so it's also safe to read from a browser.
async function handleStats(env: Env): Promise<Response> {
  const pkgs = await env.REG_DB.prepare(`SELECT COUNT(*) AS n FROM packages`).first<{ n: number }>();
  const vers = await env.REG_DB.prepare(
    `SELECT COUNT(*) AS n FROM versions WHERE yanked = 0`,
  ).first<{ n: number }>();
  return json(
    { packages: pkgs?.n ?? 0, versions: vers?.n ?? 0 },
    200,
    { "access-control-allow-origin": "*", "cache-control": "public, max-age=300" },
  );
}

// ── Yank / unyank (owner-only) + token revoke ─────────────────────────

async function handleYank(req: Request, env: Env, yank: boolean): Promise<Response> {
  const user = await userFromAuth(req, env);
  if (!user) return json({ error: "unauthorized" }, 401);
  const name = (req.headers.get("x-nurl-package") ?? "").toLowerCase();
  const version = req.headers.get("x-nurl-version") ?? "";
  if (!NAME_RE.test(name)) return json({ error: "invalid_name" }, 400);
  if (!VERSION_RE.test(version)) return json({ error: "invalid_version" }, 400);
  const owner = await env.REG_DB.prepare(`SELECT owner_user_id FROM packages WHERE name = ?`)
    .bind(name).first<{ owner_user_id: number }>();
  if (!owner) return json({ error: "not_found" }, 404);
  if (owner.owner_user_id !== user.id) return json({ error: "not_owner" }, 403);
  const res = await env.REG_DB.prepare(`UPDATE versions SET yanked = ? WHERE name = ? AND version = ?`)
    .bind(yank ? 1 : 0, name, version).run();
  if ((res.meta?.changes ?? 0) === 0) return json({ error: "version_not_found" }, 404);
  const idx = await readIndex(env, name);
  for (const v of idx.versions) if (v.version === version) v.yanked = yank;
  await env.REG_BUCKET.put(`index/${name}.json`, JSON.stringify(idx));
  return json({ ok: true, name, version, yanked: yank });
}

async function handleRevoke(req: Request, env: Env): Promise<Response> {
  const m = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i);
  if (!m) return json({ error: "unauthorized" }, 401);
  const hash = await hashToken(m[1].trim(), env.TOKEN_PEPPER);
  const res = await env.REG_DB.prepare(`DELETE FROM tokens WHERE token_hash = ?`).bind(hash).run();
  if ((res.meta?.changes ?? 0) === 0) return json({ error: "unknown_token" }, 401);
  return json({ ok: true, revoked: true });
}

function handleLogin(env: Env): Response {
  const state = randomToken().slice(0, 24);
  const u = new URL("https://github.com/login/oauth/authorize");
  u.searchParams.set("client_id", env.GITHUB_CLIENT_ID);
  u.searchParams.set("scope", "read:user");
  u.searchParams.set("redirect_uri", `${env.REGISTRY_URL}/auth/callback`);
  u.searchParams.set("state", state);
  return new Response(null, {
    status: 302,
    headers: {
      location: u.toString(),
      "set-cookie": `nurlreg_state=${state}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    },
  });
}

async function handleCallback(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const cookie = (req.headers.get("cookie") ?? "").match(/nurlreg_state=([^;]+)/);
  if (!code || !state || !cookie || cookie[1] !== state) {
    return json({ error: "bad_oauth_state" }, 400);
  }

  const tokRes = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      client_id: env.GITHUB_CLIENT_ID,
      client_secret: env.GITHUB_CLIENT_SECRET,
      code,
      redirect_uri: `${env.REGISTRY_URL}/auth/callback`,
    }),
  });
  const tok = (await tokRes.json()) as { access_token?: string };
  if (!tok.access_token) return json({ error: "oauth_exchange_failed" }, 502);

  const ghUser = (await (await fetch("https://api.github.com/user", {
    headers: { authorization: `Bearer ${tok.access_token}`, "user-agent": "nurl-registry" },
  })).json()) as { id: number; login: string };
  if (!ghUser.id) return json({ error: "github_user_failed" }, 502);

  const now = Date.now();
  await env.REG_DB.prepare(
    `INSERT INTO users (github_id, login, created_at) VALUES (?, ?, ?)
     ON CONFLICT(github_id) DO UPDATE SET login = excluded.login`,
  ).bind(ghUser.id, ghUser.login, now).run();
  const user = await env.REG_DB.prepare(`SELECT id FROM users WHERE github_id = ?`)
    .bind(ghUser.id).first<{ id: number }>();

  const token = randomToken();
  await env.REG_DB.prepare(
    `INSERT INTO tokens (user_id, token_hash, name, created_at) VALUES (?, ?, ?, ?)`,
  ).bind(user!.id, await hashToken(token, env.TOKEN_PEPPER), "cli", now).run();

  return htmlPage(
    "NURL registry — token",
    `<h1>Signed in as ${ghUser.login}</h1>` +
      `<p>Your publish token (shown once — store it now):</p>` +
      `<pre style="background:#f4f4f4;padding:1rem;border-radius:6px;user-select:all">${token}</pre>` +
      `<p>Use it with nurlpkg:</p>` +
      `<pre style="background:#f4f4f4;padding:1rem;border-radius:6px">export NURL_TOKEN=${token}\nnurlpkg publish</pre>`,
  );
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;

    if (req.method === "GET") {
      if (path === "/") return handleCatalog(url, env);
      if (path === "/login") return handleLogin(env);
      if (path === "/auth/callback") return handleCallback(req, env);
      if (path === "/api/v1/search") return handleSearch(url, env);
      if (path === "/api/v1/stats") return handleStats(env);
      if (path.startsWith("/packages/")) {
        return handlePackageDetail(env, decodeURIComponent(path.slice("/packages/".length)).toLowerCase());
      }
      if (path.startsWith("/index/") && path.endsWith(".json")) {
        const name = path.slice("/index/".length, -".json".length).toLowerCase();
        if (!NAME_RE.test(name)) return json({ error: "invalid_name" }, 400);
        return serveR2(env, `index/${name}.json`, "application/json");
      }
      if (path.startsWith("/files/")) {
        // /files/<name>/<version>/<relpath> — a README image from the tarball.
        const rest = path.slice("/files/".length);
        const s1 = rest.indexOf("/");
        const s2 = s1 < 0 ? -1 : rest.indexOf("/", s1 + 1);
        if (s1 < 0 || s2 < 0) return json({ error: "bad_path" }, 400);
        const fname = decodeURIComponent(rest.slice(0, s1)).toLowerCase();
        const fver = decodeURIComponent(rest.slice(s1 + 1, s2));
        const frel = decodeURIComponent(rest.slice(s2 + 1));
        return handleFile(env, fname, fver, frel);
      }
      if (path.startsWith("/pkgs/")) {
        // pkgs/<name>/<file>.tar.gz (+ optional .minisig) — reject traversal.
        if (path.includes("..")) return json({ error: "bad_path" }, 400);
        if (path.endsWith(".tar.gz.minisig")) return serveR2(env, path.slice(1), "text/plain");
        if (path.endsWith(".tar.gz")) return serveR2(env, path.slice(1), "application/gzip");
        return json({ error: "bad_path" }, 400);
      }
      return json({ error: "not_found" }, 404);
    }

    if (req.method === "POST") {
      if (path === "/api/v1/publish") return handlePublish(req, env);
      if (path === "/api/v1/yank") return handleYank(req, env, true);
      if (path === "/api/v1/unyank") return handleYank(req, env, false);
      if (path === "/api/v1/revoke") return handleRevoke(req, env);
      if (path === "/api/v1/admin/sign-backfill") return handleSignBackfill(req, env);
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;
