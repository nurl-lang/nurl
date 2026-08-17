#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/pqc_test.sh — end-to-end test of the pqc CLI.
#
#  The load-bearing assertion is `kat`: NIST's ACVP vectors are the only
#  oracle a KEM has. Encapsulating and decapsulating with the same
#  broken implementation still produces matching shared secrets, so a
#  round trip on its own proves nothing about correctness — only about
#  self-consistency. Both are checked here, in that order of importance.
#
#    1. kat — NIST ACVP key-generation vectors at all three sets
#    2. keygen writes keys of exactly the standard's sizes
#    3. encaps → decaps recovers the same shared secret
#    4. a corrupted ciphertext still decapsulates (implicit rejection)
#       and yields a DIFFERENT secret — never an error, never the real one
#    5. a truncated ciphertext is refused, not crashed on
#    6. a file that is not a key is refused by its length
#    7. all three parameter sets round-trip
#
#  Run from the package dir:  ./tests/pqc_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."

if [ -n "${NURL:-}" ]; then :;
elif [ -x "../../nurl.sh" ]; then NURL="../../nurl.sh";
else NURL="nurl"; fi

WORK="$(mktemp -d -t pqc-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

PQC="$WORK/pqc"
if ! $NURL src/main.nu "$PQC" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build src/main.nu:"; tail -20 "$WORK/build.err"; exit 1
fi

fails=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

echo "pqc test"

# 1. NIST vectors
if "$PQC" kat | grep -q FAIL; then bad "kat"; else ok "kat (NIST ACVP vectors)"; fi

# 2, 3, 7. sizes and round trip at every parameter set
for lv in 512 768 1024; do
    case $lv in
        512)  ek=800;  dk=1632; ct=768  ;;
        768)  ek=1184; dk=2400; ct=1088 ;;
        1024) ek=1568; dk=3168; ct=1568 ;;
    esac
    "$PQC" keygen -l $lv -o "$WORK/k$lv" >/dev/null || bad "keygen $lv"
    check "ek size $lv"  "$(wc -c < "$WORK/k$lv.ek")"  "$ek"
    check "dk size $lv"  "$(wc -c < "$WORK/k$lv.dk")"  "$dk"

    s1=$("$PQC" encaps "$WORK/k$lv.ek" -o "$WORK/c$lv" | awk '/shared secret/{print $3}')
    check "ct size $lv"  "$(wc -c < "$WORK/c$lv")"     "$ct"
    s2=$("$PQC" decaps "$WORK/k$lv.dk" "$WORK/c$lv" | awk '/shared secret/{print $3}')
    check "round trip $lv" "$s2" "$s1"
    [ -n "$s1" ] || bad "round trip $lv produced no secret"
done

# 4. implicit rejection: a corrupted ciphertext decapsulates to a
#    different, deterministic secret rather than failing.
cp "$WORK/c768" "$WORK/bad.ct"
printf '\xff' | dd of="$WORK/bad.ct" bs=1 seek=0 count=1 conv=notrunc status=none
sbad=$("$PQC" decaps "$WORK/k768.dk" "$WORK/bad.ct" | awk '/shared secret/{print $3}')
sgood=$("$PQC" decaps "$WORK/k768.dk" "$WORK/c768" | awk '/shared secret/{print $3}')
if [ -z "$sbad" ]; then bad "implicit rejection returned nothing"
elif [ "$sbad" = "$sgood" ]; then bad "implicit rejection returned the true secret"
else ok "implicit rejection (different secret, no error)"; fi
# and it must be deterministic — same input, same output
sbad2=$("$PQC" decaps "$WORK/k768.dk" "$WORK/bad.ct" | awk '/shared secret/{print $3}')
check "implicit rejection is deterministic" "$sbad2" "$sbad"

# 5. a truncated ciphertext is refused
head -c 100 "$WORK/c768" > "$WORK/short.ct"
if "$PQC" decaps "$WORK/k768.dk" "$WORK/short.ct" >/dev/null 2>&1; then
    bad "truncated ciphertext accepted"
else ok "truncated ciphertext refused"; fi

# 6. a non-key file is refused
echo "not a key" > "$WORK/junk"
if "$PQC" encaps "$WORK/junk" -o "$WORK/x.ct" >/dev/null 2>&1; then
    bad "junk accepted as an encapsulation key"
else ok "junk refused as an encapsulation key"; fi

# an out-of-range level is refused rather than rounded
if "$PQC" keygen -l 999 -o "$WORK/n" >/dev/null 2>&1; then
    bad "level 999 accepted"
else ok "invalid level refused"; fi

echo
if [ "$fails" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAIL ($fails)"; exit 1; fi
