#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  buildwasm.sh — compile compiler/nurlc.nu to nurlc.wasm via
#  the local NURL API (POST /build_wasm).
#
#  Why through the API and not directly?
#    The wasm pipeline needs:
#      - native nurlc       (.nu  → LLVM IR)
#      - IR rewriter        (i64↔i32 libc shims, c"..." mask, main rename)
#      - wasi-sdk clang     (IR + runtime.wasm.o → .wasm)
#      - wasi-libc sysroot, runtime.wasm.o, etc.
#    All of that lives inside the API container (api/Dockerfile).
#    Replicating it on the host would mean installing wasi-sdk and
#    rebuilding the wasm runtime — pointless when the container
#    already has the toolchain wired up correctly.
#
#  Usage:
#    ./startdev.sh        # in another terminal: brings up API on :8000
#    ./buildwasm.sh       # writes ./nurlc.wasm
#    ./buildwasm.sh foo.wasm  # custom output path
#
#  Env:
#    NURL_API_URL   override base URL (default http://localhost:8000)
#    NURL_SRC       override source file (default compiler/nurlc.nu)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_URL="${NURL_API_URL:-http://localhost:8000}"
SRC="${NURL_SRC:-$SCRIPT_DIR/compiler/nurlc.nu}"
OUT="${1:-$SCRIPT_DIR/nurlc.wasm}"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: source not found: $SRC" >&2
    exit 1
fi

# ── Probe API ────────────────────────────────────────────────
if ! curl -fsS --max-time 3 "$API_URL/health" >/dev/null 2>&1; then
    echo "ERROR: NURL API not reachable at $API_URL" >&2
    echo "       Start it first:  ./startdev.sh" >&2
    echo "       (or set NURL_API_URL to a running instance)" >&2
    exit 1
fi

# ── Build JSON request body ──────────────────────────────────
# jq -Rs slurps the whole file as a single JSON string, then we
# wrap it with the filename + binary return_format.
REQ_JSON=$(jq -Rs --arg name "$(basename "$SRC")" \
    '{source: ., filename: $name, return_format: "binary"}' \
    < "$SRC")

echo "[1/1] $SRC → $OUT  (via $API_URL/build_wasm)"

# ── POST to /build_wasm ──────────────────────────────────────
# We want the raw wasm body on success but a readable error on
# failure. Use -w to capture HTTP status alongside the body file.
TMP_BODY=$(mktemp -t nurlc-wasm.XXXXXX)
trap 'rm -f "$TMP_BODY"' EXIT

HTTP_CODE=$(curl -sS -o "$TMP_BODY" -w '%{http_code}' \
    -X POST "$API_URL/build_wasm" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/wasm' \
    --data-binary "@-" <<< "$REQ_JSON")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "ERROR: build failed (HTTP $HTTP_CODE)" >&2
    # Server returned JSON with stage/stderr — pretty-print if it parses.
    if jq . "$TMP_BODY" >/dev/null 2>&1; then
        jq . "$TMP_BODY" >&2
    else
        cat "$TMP_BODY" >&2
    fi
    exit 1
fi

# Sanity-check the magic bytes — guards against the API ever
# silently returning something that isn't a wasm module.
MAGIC=$(head -c 4 "$TMP_BODY" | od -An -tx1 | tr -d ' \n')
if [[ "$MAGIC" != "0061736d" ]]; then
    echo "ERROR: response is not a wasm module (magic=$MAGIC)" >&2
    head -c 512 "$TMP_BODY" >&2
    echo >&2
    exit 1
fi

mv "$TMP_BODY" "$OUT"
trap - EXIT

SIZE=$(wc -c < "$OUT")
echo ""
echo "Done: $OUT  ($SIZE bytes)"
echo ""
echo "Try:"
echo "  ./wasmnurl.sh examples/showcase.nu   # uses nurlc.wasm to build a native binary"
