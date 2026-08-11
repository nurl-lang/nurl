// test-recovery.ts — unit tests for the container-proxy recovery policy.
// Run with: npm run test:recovery  (Node 24 executes .ts natively)
//
// Covers the exact 500 body the @cloudflare/containers proxy returns for the
// production wedge, plus the transient and genuine-app cases, and the
// per-attempt action decision the fetch loop in src/index.ts is built on.

import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyError, decideAction, stampAction } from "./src/recovery.ts";

// The literal string the user observed at https://play.nurl-lang.org/.
const PROD_WEDGE =
  "Error proxying request to container: The container is not listening in the TCP address 10.0.0.1:8000";

// The literal string observed fleet-wide during the v0.37.0 image rollout —
// the DO proxied to an instance that no longer existed.
const PROD_NOT_RUNNING =
  "Error proxying request to container: The container is not running, consider calling start()";

test("classifyError: the production wedge body → 'wedged'", () => {
  assert.equal(classifyError(PROD_WEDGE), "wedged");
});

test("classifyError: the production not-running body → 'wedged'", () => {
  assert.equal(classifyError(PROD_NOT_RUNNING), "wedged");
});

test("classifyError: case-insensitive marker match", () => {
  assert.equal(classifyError("THE CONTAINER IS NOT LISTENING ..."), "wedged");
});

test("classifyError: mid-restart bodies → 'transient'", () => {
  assert.equal(classifyError("Container suddenly disconnected, try again"), "transient");
  assert.equal(
    classifyError("Error proxying request to container: Network connection lost."),
    "transient",
  );
  assert.equal(classifyError("Failed to start container: boom"), "transient");
});

test("classifyError: a genuine nurlapi 500 → 'app'", () => {
  assert.equal(classifyError("internal error: handler panicked\n"), "app");
  assert.equal(classifyError("{\"error\":\"compile failed\"}"), "app");
});

const MAX = 2;

test("decideAction: success and non-proxy statuses pass through", () => {
  assert.equal(decideAction(200, "ok", 0, MAX), "return");
  assert.equal(decideAction(404, "nope", 0, MAX), "return");
  assert.equal(decideAction(503, "no instance", 0, MAX), "return");
});

test("decideAction: wedged 500 recycles until retries are spent", () => {
  assert.equal(decideAction(500, PROD_WEDGE, 0, MAX), "recycle");
  assert.equal(decideAction(500, PROD_WEDGE, 1, MAX), "recycle");
  // Out of retries → surface the error instead of looping forever.
  assert.equal(decideAction(500, PROD_WEDGE, MAX, MAX), "return");
});

test("decideAction: transient 500 retries without a teardown", () => {
  assert.equal(decideAction(500, "Network connection lost.", 0, MAX), "retry");
});

test("decideAction: a genuine app 500 is never recycled", () => {
  assert.equal(decideAction(500, "internal error: handler panicked\n", 0, MAX), "return");
});

test("stampAction: known differing stamp always recycles; match never", () => {
  assert.equal(stampAction("abc", "def", undefined), "recycle");
  assert.equal(stampAction("abc", "def", "abc"), "recycle");
  assert.equal(stampAction("abc", "abc", undefined), "skip");
  assert.equal(stampAction(undefined, "def", undefined), "skip");
  assert.equal(stampAction("", "def", undefined), "skip");
});

test("stampAction: missing stamp recycles once per deploy id", () => {
  assert.equal(stampAction("abc", undefined, undefined), "recycle");
  assert.equal(stampAction("abc", "", undefined), "recycle");
  assert.equal(stampAction("abc", undefined, "abc"), "skip");
  assert.equal(stampAction("abc", undefined, "old-deploy"), "recycle");
});
