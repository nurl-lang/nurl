#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/lsmdb_test.sh — end-to-end test of the lsmdb CLI.
#
#  Every command is a separate process, so persistence and reopen are
#  exercised by construction: if a write did not reach disk, the NEXT
#  assertion in this file fails.
#
#    1. put / get round-trip, including binary-ish and empty values
#    2. overwrite wins; delete really deletes (and stays deleted after a
#       flush, i.e. the tombstone shadows the older table)
#    3. ordered scans: full, range, limit
#    4. flush → the same answers come out of an SSTable instead of RAM
#    5. bulk load from stdin
#    6. snapshot reads: --at N sees the database as it was after write N
#    7. compaction keeps every live key, drops the dead ones, and leaves
#       exactly one table behind
#    8. THE POINT, part 1 — crash safety: truncating the log mid-record
#       (what kill -9 during an append leaves) loses only the torn write;
#       everything acknowledged before it is still there
#    9. THE POINT, part 2 — corruption is an error, never data: flipping
#       one byte inside a table makes reads FAIL loudly instead of
#       returning something wrong
#
#  Run from the package dir:  ./tests/lsmdb_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t lsmdb-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

echo "[1/3] build lsmdb"
if ! $NURL src/main.nu "$WORK/lsmdb" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build lsmdb:"; tail -20 "$WORK/build.err"; exit 1
fi
DB="$WORK/db"
L() { "$WORK/lsmdb" -d "$DB" "$@"; }

echo "[2/3] behaviour"

# ── 1. put / get ────────────────────────────────────────────────────
L put alpha "first value" || bad "put alpha"
L put beta  "second"      || bad "put beta"
L put gamma ""            || bad "put gamma (empty value)"
eq "get returns the value"        "$(L get alpha)" "first value"
eq "get returns an empty value"   "$(L get gamma)" ""
L get nosuchkey >/dev/null 2>&1 && bad "absent key reported as found" || ok "absent key exits 1"

# Values with spaces, tabs, quotes, UTF-8 and a newline survive.
printf 'weird\tvalue "with" ⚡ bytes' > "$WORK/weird.txt"
L put weird "$(cat "$WORK/weird.txt")" || bad "put weird"
L get weird -r > "$WORK/weird.out"
cmp -s "$WORK/weird.txt" "$WORK/weird.out" && ok "binary-ish value round-trips byte for byte" || bad "weird value round-trip"

# ── 2. overwrite + delete ───────────────────────────────────────────
L put alpha "second value"
eq "overwrite wins" "$(L get alpha)" "second value"
L del beta
L get beta >/dev/null 2>&1 && bad "deleted key still readable" || ok "delete removes the key"

# ── 3. scans ────────────────────────────────────────────────────────
for k in s01 s02 s03 s04 s05; do L put "$k" "v-$k"; done
eq "scan is ordered"       "$(L scan --from s01 --to s99 | cut -f1 | tr '\n' ' ')" "s01 s02 s03 s04 s05 "
eq "scan honours --limit"  "$(L scan --from s01 --limit 2 | cut -f1 | tr '\n' ' ')" "s01 s02 "
eq "scan range is half-open" "$(L scan --from s02 --to s04 | cut -f1 | tr '\n' ' ')" "s02 s03 "
eq "scan carries values"   "$(L scan --from s03 --limit 1)" "$(printf 's03\tv-s03')"

# ── 4. flush: the same answers, now from a table ────────────────────
BEFORE="$(L scan)"
L flush >/dev/null || bad "flush"
[ "$(ls "$DB"/*.sst 2>/dev/null | wc -l)" -ge 1 ] && ok "flush wrote a table" || bad "no table after flush"
eq "flushed data reads back identically" "$(L scan)" "$BEFORE"
eq "get works from a table"              "$(L get alpha)" "second value"
L get beta >/dev/null 2>&1 && bad "tombstone lost across flush" || ok "tombstone survives the flush"

# ── 5. bulk load ────────────────────────────────────────────────────
printf 'l1\tone\nl2\ttwo\nl3\tthree\n' | L load >/dev/null || bad "load"
eq "bulk load stored every row" "$(L scan --from l1 --to l9 | wc -l | tr -d ' ')" "3"
eq "bulk loaded value"          "$(L get l2)" "two"

# ── 6. snapshot reads ───────────────────────────────────────────────
L put snap v1
SEQ1="$(L stats | awk '/^sequence/{print $2}')"
L put snap v2
eq "current read sees the new value" "$(L get snap)" "v2"
eq "snapshot read sees the old one"  "$(L get snap --at "$SEQ1")" "v1"
eq "snapshot scan sees the old one"  "$(L scan --from snap --to snapz --at "$SEQ1")" "$(printf 'snap\tv1')"

# ── 7. compaction ───────────────────────────────────────────────────
L flush >/dev/null
BEFORE="$(L scan)"
L compact >/dev/null || bad "compact"
eq "compaction keeps exactly the live data" "$(L scan)" "$BEFORE"
eq "compaction leaves one table"            "$(ls "$DB"/*.sst | wc -l | tr -d ' ')" "1"
L get beta >/dev/null 2>&1 && bad "deleted key resurrected by compaction" || ok "deleted key stays deleted"

# ── 8. crash safety: a torn log tail ────────────────────────────────
CRASH="$WORK/crash"
C() { "$WORK/lsmdb" -d "$CRASH" "$@"; }
C put k1 alive1 && C put k2 alive2 && C put k3 alive3 || bad "crash-setup writes"
# Simulate kill -9 in the middle of the NEXT append: add a half record.
printf '\xde\xad\xbe\xef\x40\x00\x00\x00partial' >> "$CRASH/WAL"
eq "committed writes survive a torn tail (1)" "$(C get k1)" "alive1"
eq "committed writes survive a torn tail (3)" "$(C get k3)" "alive3"
C put k4 alive4 || bad "database still writable after recovery"
eq "database keeps working after recovery"    "$(C get k4)" "alive4"
eq "the torn record did not become a key"     "$(C scan | wc -l | tr -d ' ')" "4"

# A log truncated mid-record (the other half of the same crash) is the
# same story: the partial write is dropped, the rest is kept.
C flush >/dev/null
C put k5 alive5
SZ=$(wc -c < "$CRASH/WAL")
dd if="$CRASH/WAL" of="$CRASH/WAL.cut" bs=1 count=$((SZ - 3)) 2>/dev/null
mv "$CRASH/WAL.cut" "$CRASH/WAL"
C get k5 >/dev/null 2>&1 && bad "a truncated write was applied anyway" || ok "a truncated write is dropped"
eq "everything before it is intact" "$(C get k1)" "alive1"

# ── 9. corruption is an error, never data ───────────────────────────
ROT="$WORK/rot"
R() { "$WORK/lsmdb" -d "$ROT" "$@"; }
for k in r1 r2 r3 r4 r5; do R put "$k" "value-of-$k"; done
R flush >/dev/null
SST=$(ls "$ROT"/*.sst | head -1)
printf 'X' | dd of="$SST" bs=1 seek=5 conv=notrunc 2>/dev/null
if R scan >/dev/null 2>&1; then bad "corrupt table read as if it were fine"; else ok "corrupt block fails the read"; fi
R scan 2>&1 | grep -qi "checksum" && ok "the error names the checksum" || bad "unhelpful corruption error"

echo "[3/3] done"
echo "== lsmdb tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
