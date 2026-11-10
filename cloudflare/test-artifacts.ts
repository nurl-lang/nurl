// test-artifacts.ts — unit tests for the artifact-persistence policy.
// Run with: npm run test:artifacts  (Node 24 executes .ts natively)
//
// Covers the token shapes nurlapi actually emits (both the REST /build* JSON
// and MCP tool-call text), the traversal/charset rejections the R2 keyspace
// depends on, and the request-classification the fetch handler is built on.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ARTIFACT_CONTENT_TYPE,
  artifactResponseHeaders,
  isSafeToken,
  downloadKey,
  extractArtifactTokens,
  shouldScanForArtifacts,
  MAX_TOKENS_PER_RESPONSE,
} from "./src/artifacts.ts";

test("isSafeToken: real nurlapi tokens pass", () => {
  assert.equal(isSafeToken("1754730000123456/main.wasm"), true);
  assert.equal(isSafeToken("1754730000123456/prog"), true);
  assert.equal(isSafeToken("1754730000123456/prog.ll"), true);
  assert.equal(isSafeToken("1754730000123456/prog.exe"), true);
});

test("isSafeToken: traversal and malformed shapes are rejected", () => {
  assert.equal(isSafeToken("../etc/passwd"), false);
  assert.equal(isSafeToken("id/.."), false);
  assert.equal(isSafeToken("id/."), false);
  assert.equal(isSafeToken("id"), false);
  assert.equal(isSafeToken("id/a/b"), false);
  assert.equal(isSafeToken("id/"), false);
  assert.equal(isSafeToken("/name"), false);
  assert.equal(isSafeToken("id/na me"), false);
  assert.equal(isSafeToken("id/na%2Fme"), false);
  assert.equal(isSafeToken("x".repeat(129) + "/name"), false);
});

test("downloadKey: maps download paths, ignores everything else", () => {
  assert.equal(downloadKey("/download/123/main.wasm"), "123/main.wasm");
  assert.equal(downloadKey("/download/123/../secret"), null);
  assert.equal(downloadKey("/download/123"), null);
  assert.equal(downloadKey("/build"), null);
  assert.equal(downloadKey("/"), null);
});

test("extractArtifactTokens: REST /build JSON shape", () => {
  const body = JSON.stringify({
    ok: true,
    ll_artifact: {
      name: "prog.ll",
      bytes: 12345,
      download_url: "https://play.nurl-lang.org/download/1754730000123456/prog.ll",
      token: "1754730000123456/prog.ll",
    },
    binary_artifact: {
      name: "prog",
      bytes: 54321,
      download_url: "https://play.nurl-lang.org/download/1754730000123456/prog",
      token: "1754730000123456/prog",
    },
  });
  assert.deepEqual(extractArtifactTokens(body), [
    "1754730000123456/prog.ll",
    "1754730000123456/prog",
  ]);
});

test("extractArtifactTokens: MCP tool-call text (URLs inside JSON-encoded string)", () => {
  const body =
    '{"jsonrpc":"2.0","result":{"content":[{"type":"text","text":' +
    '"BUILD OK\\nwasm: https://play.nurl-lang.org/download/175/m.wasm\\n' +
    'll: https://play.nurl-lang.org/download/175/m.ll"}]}}';
  assert.deepEqual(extractArtifactTokens(body), ["175/m.wasm", "175/m.ll"]);
});

test("extractArtifactTokens: duplicates collapse, no-match bodies yield nothing", () => {
  const twice = "see /download/1/a and again /download/1/a";
  assert.deepEqual(extractArtifactTokens(twice), ["1/a"]);
  assert.deepEqual(extractArtifactTokens('{"error":"compile failed"}'), []);
});

test("extractArtifactTokens: fan-out is capped", () => {
  const body = Array.from({ length: 40 }, (_, i) => `/download/1/f${i}`).join(" ");
  assert.equal(extractArtifactTokens(body).length, MAX_TOKENS_PER_RESPONSE);
});

test("shouldScanForArtifacts: build + mcp POSTs only", () => {
  assert.equal(shouldScanForArtifacts("POST", "/build"), true);
  assert.equal(shouldScanForArtifacts("POST", "/build_wasm"), true);
  assert.equal(shouldScanForArtifacts("POST", "/build_unikernel"), true);
  assert.equal(shouldScanForArtifacts("POST", "/mcp"), true);
  assert.equal(shouldScanForArtifacts("GET", "/mcp"), false);
  assert.equal(shouldScanForArtifacts("POST", "/authorize"), false);
  assert.equal(shouldScanForArtifacts("POST", "/"), false);
});

// An artifact's name is chosen by whoever asked for the build. Objects
// mirrored before the download contract kept the Content-Type the container
// derived from that name, so the contract has to hold on read, whatever the
// stored metadata or the container says.
test("artifactResponseHeaders: an object stored as text/html is served as a download", () => {
  const stored = new Headers({ "Content-Type": "text/html; charset=utf-8" });
  const h = artifactResponseHeaders(stored);
  assert.equal(h.get("Content-Type"), ARTIFACT_CONTENT_TYPE);
  assert.equal(h.get("Content-Type"), "application/octet-stream");
  assert.equal(h.get("Content-Disposition"), "attachment");
  assert.equal(h.get("X-Content-Type-Options"), "nosniff");
  // The source's headers are not modified.
  assert.equal(stored.get("Content-Type"), "text/html; charset=utf-8");
});

test("artifactResponseHeaders: no metadata at all still yields the full contract", () => {
  for (const h of [artifactResponseHeaders(), artifactResponseHeaders(new Headers())]) {
    assert.equal(h.get("Content-Type"), "application/octet-stream");
    assert.equal(h.get("Content-Disposition"), "attachment");
    assert.equal(h.get("X-Content-Type-Options"), "nosniff");
  }
});

test("artifactResponseHeaders: an inline disposition or a sniffable type from the source is overridden", () => {
  const h = artifactResponseHeaders(
    new Headers({
      "Content-Type": "image/svg+xml",
      "Content-Disposition": 'inline; filename="x.svg"',
      "X-Content-Type-Options": "",
      "Content-Length": "42",
      "Cache-Control": "max-age=60",
    }),
  );
  assert.equal(h.get("Content-Type"), "application/octet-stream");
  assert.equal(h.get("Content-Disposition"), "attachment");
  assert.equal(h.get("X-Content-Type-Options"), "nosniff");
  // Everything else the source said is passed through.
  assert.equal(h.get("Content-Length"), "42");
  assert.equal(h.get("Cache-Control"), "max-age=60");
});
