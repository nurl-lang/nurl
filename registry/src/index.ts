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
import { extractReadme, extractFile, normalizeRelPath } from "./readme.ts";

export interface Env {
  REG_BUCKET: R2Bucket;
  REG_DB: D1Database;
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string; // wrangler secret
  TOKEN_PEPPER: string;         // wrangler secret
  REGISTRY_URL: string;         // public base, e.g. https://reg.nurl-lang.org
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

  // Write tarball + updated index to R2.
  await env.REG_BUCKET.put(`pkgs/${name}/${name}-${version}.tar.gz`, body);
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
  `.readme hr{border:0;border-top:1px solid #e5e5e5;margin:2rem 0}`;

function htmlPage(title: string, bodyHtml: string, status = 200): Response {
  return new Response(
    `<!doctype html><meta charset=utf-8><title>${title}</title>` +
      `<meta name=viewport content="width=device-width,initial-scale=1">` +
      `<style>${PAGE_STYLE}</style>` +
      `<body>${bodyHtml}</body>`,
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
    `<h1>NURL package registry</h1>` +
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
  const versionsHtml = newestFirst.map((v) =>
    `<li><code>${esc(v.version)}</code>${v.yanked ? ` <span style="color:#b00">(yanked)</span>` : ""}</li>`).join("");
  const depsHtml = latest && latest.deps.length
    ? `<ul>${latest.deps.map((d) =>
        `<li><a href="/packages/${esc(d.name)}">${esc(d.name)}</a> <code>${esc(d.req)}</code></li>`).join("")}</ul>`
    : `<p>None.</p>`;
  const reqStr = latest ? `^${latest.version}` : "*";

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
          const norm = normalizeRelPath(u);
          return norm ? base + norm : u;
        };
        readmeHtml = `<div class="readme">${renderMarkdown(md, resolve)}</div>`;
      }
    } catch { /* fall through with no README */ }
  }

  return htmlPage(name,
    `<p><a href="/">← all packages</a></p><h1>${esc(name)}</h1>` +
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
        // pkgs/<name>/<file>.tar.gz — reject traversal.
        if (path.includes("..") || !path.endsWith(".tar.gz")) return json({ error: "bad_path" }, 400);
        return serveR2(env, path.slice(1), "application/gzip");
      }
      return json({ error: "not_found" }, 404);
    }

    if (req.method === "POST") {
      if (path === "/api/v1/publish") return handlePublish(req, env);
      if (path === "/api/v1/yank") return handleYank(req, env, true);
      if (path === "/api/v1/unyank") return handleYank(req, env, false);
      if (path === "/api/v1/revoke") return handleRevoke(req, env);
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;
