#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/stress_test.sh — the differential test: an lsmdb database and a
#  plain sorted text file are fed exactly the same writes, and the whole
#  contents of the database must equal the text file, byte for byte,
#  after every phase.
#
#  It is the shape that finds real bugs, because it does not check a
#  property someone thought of — it checks EVERYTHING at once:
#  ordering, versioning, tombstones, block boundaries, the index binary
#  search, the Bloom filter, the merge across N tables, and compaction.
#
#  Phases: 4 loads with a flush after each (so reads must merge four
#  tables plus the memtable) → delete a seventh of the keys → overwrite
#  another seventh → compact → reopen. The oracle is recomputed with
#  sort/awk at every step.
#
#  Run from the package dir:  ./tests/stress_test.sh [rows_per_chunk]
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

N="${1:-5000}"
WORK="$(mktemp -d -t lsmdb-stress.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] build"
if ! $NURL src/main.nu "$WORK/lsmdb" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build lsmdb:"; tail -20 "$WORK/build.err"; exit 1
fi
DB="$WORK/db"
L() { "$WORK/lsmdb" -d "$DB" "$@"; }

# The oracle: model.tsv holds the current key<TAB>value of every live
# key. `expect` sorts it the way the database orders keys (bytewise) and
# diffs it against a full scan.
MODEL="$WORK/model.tsv"
: > "$MODEL"
expect() {
    LC_ALL=C sort -u -k1,1 "$MODEL" > "$WORK/want.tsv"
    L scan > "$WORK/got.tsv" || { bad "$1 (scan failed)"; return; }
    if diff -q "$WORK/want.tsv" "$WORK/got.tsv" >/dev/null; then
        ok "$1 ($(wc -l < "$WORK/got.tsv" | tr -d ' ') keys)"
    else
        bad "$1"
        echo "    first differences:"; diff "$WORK/want.tsv" "$WORK/got.tsv" | head -6 | sed 's/^/    /'
    fi
}

# Values are long enough that a few thousand rows span many 4 KiB blocks,
# and vary in length so entries do not align to a convenient boundary.
gen() {  # gen <start> <count> <tag>
    awk -v s="$1" -v n="$2" -v tag="$3" 'BEGIN{
        for (i = s; i < s + n; i++) {
            pad = ""
            for (j = 0; j < (i % 37); j++) pad = pad "x"
            printf "key:%08d\tval-%s-%d-%s\n", i, tag, i, pad
        }
    }'
}

echo "[2/3] phases"

# ── four chunks, a flush after each → four tables ───────────────────
for c in 0 1 2 3; do
    gen $((c * N)) "$N" "c$c" > "$WORK/chunk.tsv"
    L load < "$WORK/chunk.tsv" >/dev/null || bad "load chunk $c"
    cat "$WORK/chunk.tsv" >> "$MODEL"
    L flush >/dev/null || bad "flush $c"
done
TABLES=$(ls "$DB"/*.sst | wc -l | tr -d ' ')
[ "$TABLES" = 4 ] && ok "four tables on disk" || bad "expected 4 tables, got $TABLES"
expect "merged scan over 4 tables matches the model"

# ── point reads: every key, from whichever table holds it ───────────
MISS=0
while IFS=$'\t' read -r k v; do
    got=$(L get "$k") || { MISS=$((MISS+1)); continue; }
    [ "$got" = "$v" ] || MISS=$((MISS+1))
done < <(LC_ALL=C sort -u -k1,1 "$MODEL" | awk 'NR % 97 == 1')
[ "$MISS" = 0 ] && ok "sampled point reads all agree" || bad "$MISS sampled point reads disagreed"

# ── absent keys must be absent (Bloom filter + index path) ──────────
GHOST=0
for i in 1 2 3 4 5 6 7 8; do
    L get "nope:$i" >/dev/null 2>&1 && GHOST=$((GHOST+1))
done
[ "$GHOST" = 0 ] && ok "absent keys stay absent" || bad "$GHOST absent keys came back"

# ── delete a seventh of the keys ────────────────────────────────────
LC_ALL=C sort -u -k1,1 "$MODEL" | awk 'NR % 7 == 0 {print $1}' > "$WORK/dead.txt"
while read -r k; do L del "$k"; done < "$WORK/dead.txt"
grep -vFf <(sed 's/$/\t/' "$WORK/dead.txt") "$MODEL" > "$WORK/model2" || true
awk 'NR==FNR{d[$1]=1;next} !($1 in d)' "$WORK/dead.txt" "$MODEL" > "$WORK/model2"
mv "$WORK/model2" "$MODEL"
expect "deletes are reflected in the merged view"

# ── overwrite another seventh ───────────────────────────────────────
LC_ALL=C sort -u -k1,1 "$MODEL" | awk 'NR % 7 == 3 {print $1"\tREWRITTEN-"NR}' > "$WORK/over.tsv"
L load < "$WORK/over.tsv" >/dev/null || bad "overwrite load"
awk 'NR==FNR{o[$1]=$2;next} {if ($1 in o) print $1"\t"o[$1]; else print}' \
    "$WORK/over.tsv" "$MODEL" > "$WORK/model2"
mv "$WORK/model2" "$MODEL"
expect "overwrites shadow the older tables"

# ── flush, reopen, compact ──────────────────────────────────────────
L flush >/dev/null
expect "after a flush of the deletes and overwrites"

KEPT=$(L compact | awk '{print $1}')
[ "$(ls "$DB"/*.sst | wc -l | tr -d ' ')" = 1 ] && ok "compaction left one table" || bad "compaction table count"
[ "$KEPT" = "$(wc -l < "$MODEL" | tr -d ' ')" ] && ok "compaction kept exactly the live keys ($KEPT)" \
    || bad "compaction kept $KEPT, model has $(wc -l < "$MODEL" | tr -d ' ')"
expect "after compaction"

# ── the deleted keys must not come back ─────────────────────────────
BACK=0
while read -r k; do L get "$k" >/dev/null 2>&1 && BACK=$((BACK+1)); done < "$WORK/dead.txt"
[ "$BACK" = 0 ] && ok "no deleted key resurrected" || bad "$BACK deleted keys came back"

# ── ranges land on the right boundaries ─────────────────────────────
FROM=$(awk 'NR==1{print $1}' "$WORK/want.tsv")
MID=$(awk 'NR==int(FNR/2)+1{print $1; exit}' "$WORK/want.tsv")
L scan --from "$MID" > "$WORK/tail.tsv"
awk -v m="$MID" '$1 >= m' "$WORK/want.tsv" > "$WORK/tailwant.tsv"
diff -q "$WORK/tailwant.tsv" "$WORK/tail.tsv" >/dev/null && ok "range scan from a mid key" || bad "range scan boundary"
[ "$(L scan --from "$FROM" --limit 3 | wc -l | tr -d ' ')" = 3 ] && ok "limit applies" || bad "limit"

echo "[3/3] done"
echo "== lsmdb stress: PASS=$PASS FAIL=$FAIL  (rows/chunk=$N)"
[ "$FAIL" = 0 ]
