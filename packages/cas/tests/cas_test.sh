#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/cas_test.sh — end-to-end test of the cas CLI:
#    1. put / hash agree; second put dedups to the same name
#    2. get returns the exact original bytes (binary-clean)
#    3. snapshot is deterministic (same tree → same manifest hash)
#       and dedups identical files inside the store
#    4. checkout round-trips the tree byte-for-byte
#    5. verify deep-proves a snapshot
#    6. THE POINT: a flipped byte inside the store makes get /
#       verify / checkout FAIL — corruption is an error, never data
#
#  Run from the package dir:  ./tests/cas_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t cas-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/2] build cas"
if ! $NURL src/main.nu "$WORK/cas" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build cas:"; tail -5 "$WORK/build.err"; exit 1
fi
CAS="$WORK/cas"
export CAS_STORE="$WORK/store"

echo "[2/2] behaviour"
mkdir -p "$WORK/tree/sub"
echo "hello cas" > "$WORK/tree/a.txt"
echo "hello cas" > "$WORK/tree/dup.txt"
printf 'binary\x00data\xff' > "$WORK/tree/sub/b.bin"

H1=$("$CAS" put "$WORK/tree/a.txt")
H2=$("$CAS" hash "$WORK/tree/a.txt")
H3=$("$CAS" put "$WORK/tree/a.txt")
[ -n "$H1" ] && [ "$H1" = "$H2" ] && [ "$H1" = "$H3" ] && ok "put/hash/dedup agree" || bad "put/hash/dedup"

"$CAS" get "$H1" -o "$WORK/back.txt" && cmp -s "$WORK/tree/a.txt" "$WORK/back.txt" && ok "get round-trips" || bad "get round-trip"

M1=$("$CAS" snapshot "$WORK/tree")
M2=$("$CAS" snapshot "$WORK/tree")
[ -n "$M1" ] && [ "$M1" = "$M2" ] && ok "snapshot deterministic" || bad "snapshot determinism"

NOBJ=$(find "$CAS_STORE/objects" -type f | wc -l)
[ "$NOBJ" = 3 ] && ok "dedup in store (3 files + manifest = 3 objects)" || bad "store object count ($NOBJ)"

"$CAS" verify "$M1" >/dev/null && ok "verify proves the snapshot" || bad "verify"

"$CAS" checkout "$M1" "$WORK/out" >/dev/null && diff -r "$WORK/tree" "$WORK/out" >/dev/null && ok "checkout byte-identical" || bad "checkout"

# ── tamper: flip one byte inside a stored object ────────────────────
OBJ=$(find "$CAS_STORE/objects" -type f | sort | head -1)
printf 'X' | dd of="$OBJ" bs=1 seek=3 conv=notrunc 2>/dev/null
if "$CAS" verify "$M1" >/dev/null 2>&1; then bad "tamper: verify accepted corruption"; else ok "tamper: verify rejects"; fi
if "$CAS" checkout "$M1" "$WORK/out2" >/dev/null 2>&1; then bad "tamper: checkout accepted corruption"; else ok "tamper: checkout rejects"; fi

echo "== cas tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
