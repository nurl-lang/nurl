// Concurrency tests for the publish path (agora #162): the real Worker over
// an in-memory D1 (node:sqlite, the same SQLite engine D1 runs) and an
// in-memory R2 with conditional puts. Every storage call yields for a
// seeded-random number of ticks, so concurrent publishes interleave at
// every await; each scenario runs under many seeds.
// Run with: node test-publish.ts   (Node >= 22.13).
import { readFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { DatabaseSync } from "node:sqlite";
import worker from "./src/index.ts";

let pass = 0, fail = 0;
function ok(cond: boolean, msg: string) {
  if (cond) { pass++; } else { fail++; console.log(`FAIL: ${msg}`); }
}

// ── seeded scheduler ──────────────────────────────────────────────────
let rng = 1;
function rand(): number {
  rng = (Math.imul(rng, 1103515245) + 12345) >>> 0;
  return rng / 2 ** 32;
}
async function tick(): Promise<void> {
  for (let n = Math.floor(rand() * 4); n > 0; n--) await new Promise((r) => setImmediate(r));
}

// ── fake D1 ───────────────────────────────────────────────────────────
class Stmt {
  db: DatabaseSync; sql: string; params: unknown[];
  constructor(db: DatabaseSync, sql: string, params: unknown[] = []) {
    this.db = db; this.sql = sql; this.params = params;
  }
  bind(...params: unknown[]): Stmt { return new Stmt(this.db, this.sql, params); }
  runSync() {
    const r = this.db.prepare(this.sql).run(...(this.params as never[]));
    return { success: true, results: [], meta: { changes: Number(r.changes) } };
  }
  async run() { await tick(); return this.runSync(); }
  async first<T>(): Promise<T | null> {
    await tick();
    return (this.db.prepare(this.sql).get(...(this.params as never[])) as T) ?? null;
  }
  async all<T>(): Promise<{ results: T[] }> {
    await tick();
    return { results: this.db.prepare(this.sql).all(...(this.params as never[])) as T[] };
  }
}
class FakeD1 {
  db = new DatabaseSync(":memory:");
  fail: ((sql: string) => boolean) | null = null;
  constructor() {
    for (const f of readdirSync("migrations").sort()) this.db.exec(readFileSync(`migrations/${f}`, "utf8"));
  }
  prepare(sql: string): Stmt { return new Stmt(this.db, sql); }
  // A D1 batch is one transaction, and runs without interleaving.
  async batch(stmts: Stmt[]) {
    await tick();
    this.db.exec("BEGIN");
    try {
      const out = stmts.map((s) => {
        if (this.fail && this.fail(s.sql)) throw new Error("injected D1 failure");
        return s.runSync();
      });
      this.db.exec("COMMIT");
      return out;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
}

// ── fake R2 ───────────────────────────────────────────────────────────
interface Obj { data: Uint8Array; etag: string; }
class FakeR2 {
  m = new Map<string, Obj>();
  n = 0;
  fail: ((key: string) => boolean) | null = null;
  async get(key: string) {
    await tick();
    const o = this.m.get(key);
    if (!o) return null;
    return {
      etag: o.etag,
      httpEtag: `"${o.etag}"`,
      get body() { return new Response(o.data).body; },
      text: async () => new TextDecoder().decode(o.data),
      arrayBuffer: async () => o.data.slice().buffer,
    };
  }
  async put(key: string, value: ArrayBuffer | string | Uint8Array, opts?: { onlyIf?: { etagMatches?: string; etagDoesNotMatch?: string } }) {
    await tick();
    if (this.fail && this.fail(key)) throw new Error("injected R2 failure");
    const cur = this.m.get(key);
    const c = opts?.onlyIf;
    if (c?.etagMatches !== undefined && (!cur || cur.etag !== c.etagMatches)) return null;
    if (c?.etagDoesNotMatch !== undefined && cur && (c.etagDoesNotMatch === "*" || cur.etag === c.etagDoesNotMatch)) return null;
    const data = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value instanceof Uint8Array ? value : new Uint8Array(value)).slice();
    const etag = `e${++this.n}`;
    this.m.set(key, { data, etag });
    return { etag };
  }
  async delete(keys: string | string[]) {
    await tick();
    for (const k of Array.isArray(keys) ? keys : [keys]) this.m.delete(k);
  }
}

// ── fixtures ──────────────────────────────────────────────────────────
const PEPPER = "pepper";
const SIGN_KEY = "AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw=";
const sha = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

function makeEnv(sign = false) {
  const d1 = new FakeD1(), r2 = new FakeR2();
  d1.db.exec(`INSERT INTO users (id, github_id, login, created_at) VALUES (1, 1, 'alice', 0), (2, 2, 'mallory', 0)`);
  for (const [uid, tok] of [[1, "tok-a"], [2, "tok-b"]] as const) {
    d1.db.prepare(`INSERT INTO tokens (user_id, token_hash, name, created_at) VALUES (?, ?, 'cli', 0)`)
      .run(uid, sha(PEPPER + tok));
  }
  const env = {
    REG_DB: d1, REG_BUCKET: r2, TOKEN_PEPPER: PEPPER, GITHUB_CLIENT_ID: "x", GITHUB_CLIENT_SECRET: "x",
    REGISTRY_URL: "http://reg/", RL_PUBLISH_PER_HOUR: "100000",
    ...(sign ? { REG_SIGN_KEY: SIGN_KEY, REG_SIGN_KEYID: "0a0b0c0d0e0f1011" } : {}),
  };
  return { d1, r2, env };
}

function tarball(name: string, author: string): Uint8Array {
  const files: [string, string][] = [
    ["nurl.toml", `[package]\nname = "${name}"\ndescription = "by ${author}"\n`],
    ["src/lib.nu", `// ${author}\n`],
  ];
  const parts: Uint8Array[] = [];
  for (const [path, body] of files) {
    const h = new Uint8Array(512);
    const put = (s: string, off: number) => h.set(new TextEncoder().encode(s), off);
    put(path, 0); put("0000644\0", 100); put("0000000\0", 108); put("0000000\0", 116);
    put(body.length.toString(8).padStart(11, "0") + "\0", 124);
    put("00000000000\0", 136); put("        ", 148); h[156] = 0x30; put("ustar\0", 257); put("00", 263);
    let sum = 0;
    for (const b of h) sum += b;
    put(sum.toString(8).padStart(6, "0") + "\0 ", 148);
    const data = new Uint8Array(Math.ceil(body.length / 512) * 512);
    data.set(new TextEncoder().encode(body));
    parts.push(h, data);
  }
  parts.push(new Uint8Array(1024));
  return gzipSync(Buffer.concat(parts));
}

async function publish(env: object, tok: string, name: string, version: string, body: Uint8Array) {
  // A throw out of the Worker is the runtime's 500.
  const res = await worker.fetch(new Request("http://reg/api/v1/publish", {
    method: "POST",
    headers: { authorization: `Bearer ${tok}`, "x-nurl-package": name, "x-nurl-version": version },
    body,
  }), env as never, {} as never).catch(() => new Response("{}", { status: 500 }));
  return { status: res.status, body: await res.json() as Record<string, unknown> };
}
async function get(env: object, path: string): Promise<Response> {
  return worker.fetch(new Request(`http://reg${path}`), env as never, {} as never);
}
async function index(env: object, name: string) {
  const r = await get(env, `/index/${name}.json`);
  return r.status === 200 ? (await r.json() as { versions: { version: string; checksum: string; yanked: boolean }[] }).versions : [];
}

const SEEDS = 40;

// ── same unclaimed name, same version, two users ─────────────────────
for (let seed = 1; seed <= SEEDS; seed++) {
  rng = seed;
  const { d1, r2, env } = makeEnv(seed % 4 === 0);
  const ta = tarball("pkg", "alice"), tb = tarball("pkg", "mallory");
  const [a, b] = await Promise.all([
    publish(env, "tok-a", "pkg", "1.0.0", ta),
    publish(env, "tok-b", "pkg", "1.0.0", tb),
  ]);
  const wins = [a, b].filter((r) => r.status === 200).length;
  ok(wins === 1, `seed ${seed}: same name+version, exactly one publish wins (got ${a.status}/${b.status})`);
  const loser = a.status === 200 ? b : a;
  ok(loser.status === 403 || loser.status === 409, `seed ${seed}: the loser gets 403/409 (got ${loser.status})`);
  const winBytes = a.status === 200 ? ta : tb, winUid = a.status === 200 ? 1 : 2;
  const pkg = d1.db.prepare(`SELECT owner_user_id FROM packages WHERE name = 'pkg'`).get() as { owner_user_id: number };
  const ver = d1.db.prepare(`SELECT checksum, published_by, pending FROM versions WHERE name = 'pkg'`).all() as { checksum: string; published_by: number; pending: number }[];
  ok(pkg?.owner_user_id === winUid, `seed ${seed}: D1 owner is the winner`);
  ok(ver.length === 1 && ver[0].checksum === sha(winBytes) && ver[0].published_by === winUid && ver[0].pending === 0,
    `seed ${seed}: one committed D1 version, the winner's checksum`);
  const idx = await index(env, "pkg");
  ok(idx.length === 1 && idx[0].checksum === sha(winBytes), `seed ${seed}: index holds the winner's checksum only`);
  const served = new Uint8Array(await (await get(env, "/pkgs/pkg/pkg-1.0.0.tar.gz")).arrayBuffer());
  ok(sha(served) === sha(winBytes), `seed ${seed}: the served tarball is the winner's`);
  if (seed % 4 === 0) ok(r2.m.has("pkgs/pkg/pkg-1.0.0.tar.gz.minisig"), `seed ${seed}: signed publish has its .minisig`);
}

// ── same unclaimed name, different versions, two users ───────────────
for (let seed = 1; seed <= SEEDS; seed++) {
  rng = seed * 7919;
  const { d1, r2, env } = makeEnv();
  const [a, b] = await Promise.all([
    publish(env, "tok-a", "dup", "1.0.0", tarball("dup", "alice")),
    publish(env, "tok-b", "dup", "2.0.0", tarball("dup", "mallory")),
  ]);
  ok([a, b].filter((r) => r.status === 200).length === 1, `seed ${seed}: different versions, one owner wins (got ${a.status}/${b.status})`);
  const loserVer = a.status === 200 ? "2.0.0" : "1.0.0", winVer = a.status === 200 ? "1.0.0" : "2.0.0";
  ok(!r2.m.has(`pkgs/dup/dup-${loserVer}.tar.gz`), `seed ${seed}: no tarball of the losing user is stored`);
  const idx = await index(env, "dup");
  ok(idx.length === 1 && idx[0].version === winVer, `seed ${seed}: index lists only the winner's version`);
  const n = (d1.db.prepare(`SELECT COUNT(*) AS n FROM versions WHERE name = 'dup'`).get() as { n: number }).n;
  ok(n === 1, `seed ${seed}: D1 holds only the winner's version`);
}

// ── the owner publishes many versions at once: no index update is lost ──
for (let seed = 1; seed <= SEEDS; seed++) {
  rng = seed * 104729;
  const { d1, env } = makeEnv();
  const first = await publish(env, "tok-a", "many", "0.1.0", tarball("many", "alice"));
  ok(first.status === 200, `seed ${seed}: first publish`);
  const vers = ["1.0.0", "1.1.0", "1.2.0", "2.0.0", "3.0.0"];
  const rs = await Promise.all(vers.map((v) => publish(env, "tok-a", "many", v, tarball("many", `alice ${v}`))));
  ok(rs.every((r) => r.status === 200), `seed ${seed}: all concurrent owner publishes succeed`);
  const idx = await index(env, "many");
  ok(idx.length === 6 && vers.every((v) => idx.some((e) => e.version === v)), `seed ${seed}: index keeps every version (got ${idx.map((e) => e.version)})`);
  const n = (d1.db.prepare(`SELECT COUNT(*) AS n FROM versions WHERE name = 'many' AND pending = 0`).get() as { n: number }).n;
  ok(n === 6, `seed ${seed}: D1 commits every version`);
  // A yank racing a publish keeps both changes.
  const [y, p] = await Promise.all([
    worker.fetch(new Request("http://reg/api/v1/yank", {
      method: "POST", headers: { authorization: "Bearer tok-a", "x-nurl-package": "many", "x-nurl-version": "1.0.0" },
    }), env as never, {} as never),
    publish(env, "tok-a", "many", "4.0.0", tarball("many", "alice 4")),
  ]);
  const idx2 = await index(env, "many");
  ok(y.status === 200 && p.status === 200 && idx2.length === 7 && idx2.find((e) => e.version === "1.0.0")?.yanked === true,
    `seed ${seed}: a yank racing a publish keeps both`);
}

// ── a failure after the reservation leaves nothing behind ────────────
{
  rng = 5;
  const { d1, r2, env } = makeEnv(true);
  r2.fail = (k) => k.startsWith("index/");
  const r = await publish(env, "tok-a", "boom", "1.0.0", tarball("boom", "alice"));
  ok(r.status === 500, `index write failure fails the publish (got ${r.status})`);
  ok(![...r2.m.keys()].some((k) => k.includes("boom")), "no tarball / signature / index of the failed publish remains");
  ok(d1.db.prepare(`SELECT 1 FROM packages WHERE name = 'boom'`).get() === undefined, "the failed new name is not owned");
  ok(d1.db.prepare(`SELECT 1 FROM versions WHERE name = 'boom'`).get() === undefined, "no version row remains");
  r2.fail = null;
  const other = await publish(env, "tok-b", "boom", "1.0.0", tarball("boom", "mallory"));
  ok(other.status === 200, "after the failure the name is free again");

  // A commit failure undoes the index entry and the tarball too.
  d1.fail = (sql) => sql.includes("SET pending = 0");
  const c = await publish(env, "tok-b", "boom", "1.1.0", tarball("boom", "mallory 1.1"));
  d1.fail = null;
  ok(c.status === 500, `commit failure fails the publish (got ${c.status})`);
  ok(!r2.m.has("pkgs/boom/boom-1.1.0.tar.gz") && !r2.m.has("pkgs/boom/boom-1.1.0.tar.gz.minisig"), "commit failure removes the tarball and signature");
  const idx = await index(env, "boom");
  ok(idx.length === 1 && idx[0].version === "1.0.0", "commit failure removes the index entry, keeps the committed one");
  ok(d1.db.prepare(`SELECT 1 FROM packages WHERE name = 'boom'`).get() !== undefined, "an existing package survives a failed later publish");
}

// ── a dead reservation: fresh blocks, stale is reclaimed by its publisher ──
{
  rng = 9;
  const { d1, env } = makeEnv();
  await publish(env, "tok-a", "stale", "0.1.0", tarball("stale", "alice"));
  d1.db.prepare(`INSERT INTO versions (name, version, checksum, published_by, published_at, pending) VALUES ('stale', '1.0.0', 'x', 1, ?, 1)`).run(Date.now());
  const fresh = await publish(env, "tok-a", "stale", "1.0.0", tarball("stale", "alice"));
  ok(fresh.status === 409, `a fresh reservation blocks the same version (got ${fresh.status})`);
  d1.db.prepare(`UPDATE versions SET published_at = 0 WHERE name = 'stale' AND version = '1.0.0'`).run();
  const reclaimed = await publish(env, "tok-a", "stale", "1.0.0", tarball("stale", "alice"));
  ok(reclaimed.status === 200, `a stale reservation is reclaimed by its publisher (got ${reclaimed.status})`);
  const catalog = await (await get(env, "/api/v1/stats")).json() as { versions: number };
  ok(catalog.versions === 2, `stats count committed versions (got ${catalog.versions})`);
  d1.db.prepare(`INSERT INTO versions (name, version, checksum, published_by, published_at, pending) VALUES ('stale', '9.0.0', 'x', 1, ?, 1)`).run(Date.now());
  const catalog2 = await (await get(env, "/api/v1/stats")).json() as { versions: number };
  ok(catalog2.versions === 2, "a pending version is not counted");
}

// ── two strangers racing lookalike new names: never both ─────────────
for (let seed = 1; seed <= SEEDS; seed++) {
  rng = seed * 31;
  const { env } = makeEnv();
  const [a, b] = await Promise.all([
    publish(env, "tok-a", "foobar", "1.0.0", tarball("foobar", "alice")),
    publish(env, "tok-b", "fooba", "1.0.0", tarball("fooba", "mallory")),
  ]);
  ok(!(a.status === 200 && b.status === 200), `seed ${seed}: lookalike names never both land (got ${a.status}/${b.status})`);
}

console.log(`\n==== ${pass} passed, ${fail} failed ====`);
if (fail > 0) process.exit(1);
