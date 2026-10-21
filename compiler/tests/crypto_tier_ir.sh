#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/crypto_tier_ir.sh — the hardware crypto tier
#  (nurl_v128_aes*, nurl_v128_clmul_*; docs/spec.md §4.1b), checked at
#  the level a behavioural test cannot see.
#
#  simd_crypto.nu proves the primitives compute the right thing on
#  this CPU. It cannot prove that a tier function carries the tier's
#  feature set, that its entry is gated, that it is never
#  `alwaysinline` (LLVM would inline it into a baseline caller), that
#  its inline copy exists and is what other tier code calls, that a
#  `simd` function's clones were built for the tier and its dispatcher
#  asks for AES — nor that --no-cpu-dispatch leaves no x86 intrinsic in
#  the module. A regression in any of those is a SIGILL on some CPU, an
#  LLVM "Cannot select", or a kernel that silently stopped inlining.
#  Then it runs the program with the tier taken away: the gate must
#  panic, cleanly, and the AES clone without AVX2 must still be right.
#  The VAES tier (v256) and the AVX-512 VAES tier (v512) get the same
#  checks, and what only their wide signatures need: the pointer
#  crossing of a tier function called from outside its tier
#  (emit_vabi). Last, AES-GCM's wide kernels must exist as VAES machine
#  code and agree with the software oracle with each tier taken away.
#
#  Every assertion greps for a POSITIVE marker and counts it.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/simd_crypto.nu"

[ -x "$NURLC" ] || { echo "crypto_tier_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }
[ -f "$SRC" ] || { echo "crypto_tier_ir: $SRC missing" >&2; exit 2; }

# The tier is an x86-64 feature set; elsewhere nurlc starts with it off
# and there is nothing to check but the stubs — skip loudly.
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) echo "crypto_tier_ir: skipped — $(uname -m) has no crypto tier"; exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

note() { printf '  %-56s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }
ok() { note "$1" "ok ($2)"; }

cd "$ROOT" || exit 2
"$NURLC" "$SRC" > "$WORK/on.ll" 2> "$WORK/on.err" || {
    echo "crypto_tier_ir: nurlc failed"; cat "$WORK/on.err"; exit 1; }
"$NURLC" --no-cpu-dispatch "$SRC" > "$WORK/off.ll" 2> "$WORK/off.err" || {
    echo "crypto_tier_ir: nurlc --no-cpu-dispatch failed"; cat "$WORK/off.err"; exit 1; }

TIER='"target-cpu"="x86-64-v2" "target-features"="+aes,+pclmul'

# ── 1. A plain tier function: tier attributes, gate, no alwaysinline ─
# `next_key` (v128 signature → would be alwaysinline) and `decrypt`.
for fn in next_key decrypt; do
    hdr=$(grep -E "^define .*@__nurl_fn\.${fn}[a-z0-9_]*\(" "$WORK/on.ll" | head -1)
    if [ -z "$hdr" ]; then bad "$fn: defined" "no define"; continue; fi
    case "$hdr" in *"$TIER"*) ok "$fn: compiled for the tier" "x86-64-v2 +aes +pclmul" ;;
        *) bad "$fn: compiled for the tier" "header: ${hdr:0:120}" ;; esac
    case "$hdr" in *alwaysinline*) bad "$fn: not alwaysinline" "it is" ;;
        *inlinehint*) ok "$fn: not alwaysinline" "inlinehint" ;;
        *) bad "$fn: not alwaysinline" "no inlinehint either" ;; esac
    body=$(awk -v h="$hdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
    if printf '%s\n' "$body" | grep -q 'call void @nurl__aes_gate()'; then
        ok "$fn: entry gated" "nurl__aes_gate"
    else
        bad "$fn: entry gated" "no gate call in the body"
    fi
done

# ── 2. The .tier copy: alwaysinline, linkonce_odr, ungated ──────────
# `aes_round` is called from `encrypt`, a tier function: its clones must
# call the copy, and the copy must exist (nothing else keeps it alive).
thdr=$(grep -E "^define linkonce_odr .*@__nurl_fn\.aes_round[a-z0-9_]*\.tier\(" "$WORK/on.ll" | head -1)
if [ -n "$thdr" ]; then
    case "$thdr" in *alwaysinline*"$TIER"*) ok "aes_round.tier: alwaysinline, tier attributes" "linkonce_odr" ;;
        *) bad "aes_round.tier: alwaysinline, tier attributes" "header: ${thdr:0:120}" ;; esac
    tbody=$(awk -v h="$thdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
    if printf '%s\n' "$tbody" | grep -q 'nurl__aes_gate'; then
        bad "aes_round.tier: ungated" "it calls the gate"
    else
        ok "aes_round.tier: ungated" "no gate"
    fi
else
    bad "aes_round.tier: exists" "no linkonce_odr .tier define"
fi
for clone in base x86v3; do
    chdr=$(grep -E "^define .*@__nurl_fn\.encrypt[a-z0-9_]*\.${clone}\(" "$WORK/on.ll" | head -1)
    cbody=$(awk -v h="$chdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
    if printf '%s\n' "$cbody" | grep -qE '@__nurl_fn\.aes_round[a-z0-9_]*\.tier\('; then
        ok "encrypt.$clone calls aes_round.tier" "inlined unconditionally"
    else
        bad "encrypt.$clone calls aes_round.tier" "it calls something else"
    fi
done
# `schedule` calls next_key but uses no primitive itself: it stays
# baseline and must call the GATED original, never the copy.
shdr=$(grep -E "^define .*@__nurl_fn\.schedule[a-z0-9_]*\(" "$WORK/on.ll" | head -1)
sbody=$(awk -v h="$shdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
case "$shdr" in *target-features*) bad "schedule: stays baseline" "it carries features" ;;
    *) ok "schedule: stays baseline" "no features" ;; esac
if printf '%s\n' "$sbody" | grep -qE '@__nurl_fn\.next_key[a-z0-9_]*\.tier\('; then
    bad "schedule: calls the gated next_key" "it calls the ungated .tier copy"
elif printf '%s\n' "$sbody" | grep -qE '@__nurl_fn\.next_key[a-z0-9_]*\('; then
    ok "schedule: calls the gated next_key" "not .tier"
else
    bad "schedule: calls the gated next_key" "no call found"
fi

# ── 3. A `simd` tier function: both clones for the tier, AES dispatch ─
bhdr=$(grep -E "^define .*@__nurl_fn\.encrypt[a-z0-9_]*\.base\(" "$WORK/on.ll" | head -1)
whdr=$(grep -E "^define .*@__nurl_fn\.encrypt[a-z0-9_]*\.x86v3\(" "$WORK/on.ll" | head -1)
case "$bhdr" in *"$TIER"*) ok "encrypt.base: compiled for the tier" "x86-64-v2 +aes" ;;
    *) bad "encrypt.base: compiled for the tier" "header: ${bhdr:0:120}" ;; esac
case "$whdr" in *'"target-cpu"="x86-64-v3"'*'+aes,+pclmul"'*) ok "encrypt.x86v3: v3 plus AES" "+aes,+pclmul" ;;
    *) bad "encrypt.x86v3: v3 plus AES" "header: ${whdr:0:140}" ;; esac
bbody=$(awk -v h="$bhdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
if printf '%s\n' "$bbody" | grep -q 'call void @nurl__aes_gate()'; then
    ok "encrypt.base: gated" "nurl__aes_gate"
else
    bad "encrypt.base: gated" "no gate"
fi
dhdr=$(grep -E "^define .*@__nurl_fn\.encrypt[a-z0-9_]*\(i8\* %rk, <4 x i32> %pt\) \{" "$WORK/on.ll" | head -1)
dbody=$(awk -v h="$dhdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
if printf '%s\n' "$dbody" | grep -q 'call i32 @nurl_cpu_x86_aes()' &&
        printf '%s\n' "$dbody" | grep -q 'call i32 @nurl_cpu_x86_v3()'; then
    ok "encrypt dispatcher: wide only with v3 AND the tier" "both probed"
else
    bad "encrypt dispatcher: wide only with v3 AND the tier" "missing a probe"
fi

# ── 4. --no-cpu-dispatch: no tier, no x86 intrinsic anywhere ────────
n_x86=$(grep -c 'llvm\.x86\.' "$WORK/off.ll")
n_feat=$(grep -c 'target-features' "$WORK/off.ll")
if [ "$n_x86" -eq 0 ] && [ "$n_feat" -eq 0 ]; then
    ok "--no-cpu-dispatch: no x86 intrinsic, no feature string" "0 / 0"
else
    bad "--no-cpu-dispatch: no x86 intrinsic, no feature string" "$n_x86 intrinsics, $n_feat feature strings"
fi
if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_aes()' "$WORK/off.ll" | grep -q 'ret i1 false'; then
    ok "--no-cpu-dispatch: nurl_cpu_has_aes is false" "constant"
else
    bad "--no-cpu-dispatch: nurl_cpu_has_aes is false" "not a constant false"
fi
if grep -A3 '^define linkonce_odr <4 x i32> @nurl_v128_aesenc(' "$WORK/off.ll" | grep -q 'call void @nurl_cpu_aes_missing()'; then
    ok "--no-cpu-dispatch: primitives are panicking stubs" "nurl_cpu_aes_missing"
else
    bad "--no-cpu-dispatch: primitives are panicking stubs" "aesenc is not a stub"
fi

# ── 5. Machine code, and the program with the tier taken away ───────
CLANG="${CLANG:-clang}"
if command -v "$CLANG" >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1 &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/on.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/on" -lm -lpthread 2>"$WORK/link.err"; then
    for clone in base x86v3; do
        n=$(objdump -d "$WORK/on" 2>/dev/null |
            awk -v c="$clone" '$0 ~ "^[0-9a-f]+ <[^>]*encrypt[^>]*\\." c ">:"{p=1} /^$/{p=0} p' | grep -c 'aesenc')
        if [ "$n" -gt 0 ]; then ok "encrypt.$clone lowers to AESENC" "$n"
        else bad "encrypt.$clone lowers to AESENC" "none"; fi
    done
    if grep -qw aes /proc/cpuinfo 2>/dev/null && grep -qw pclmulqdq /proc/cpuinfo 2>/dev/null; then
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/simd_crypto.txt" | tail -n +2)
        got=$(NURL_CPU_V3=0 "$WORK/on" 2>&1)
        if [ "$got" = "$want" ]; then ok "NURL_CPU_V3=0: the AES clone without AVX2 agrees" "golden"
        else bad "NURL_CPU_V3=0: the AES clone without AVX2 agrees" "output differs"; fi
        # The golden's program asks nurl_cpu_has_aes first, so taking
        # the tier away must reach its software answer — exit 1 and the
        # one line — not the gate.
        got=$(NURL_CPU_AES=0 "$WORK/on" 2>&1); rc=$?
        if [ "$rc" -eq 1 ] && [ "$got" = "no crypto tier on this CPU" ]; then
            ok "NURL_CPU_AES=0: nurl_cpu_has_aes answers false" "software branch"
        else
            bad "NURL_CPU_AES=0: nurl_cpu_has_aes answers false" "exit $rc: ${got:0:80}"
        fi
        # And a program that does NOT ask reaches the gate: a panic.
        sed 's/^    ? ! ( nurl_cpu_has_aes ).*$//' "$SRC" > "$WORK/gate.nu"
        if "$NURLC" "$WORK/gate.nu" > "$WORK/gate.ll" 2>/dev/null &&
                "$CLANG" -O2 -flto -Wno-override-module "$WORK/gate.ll" "$ROOT/stdlib/runtime.o" \
                    -o "$WORK/gate" -lm -lpthread 2>/dev/null; then
            got=$(NURL_CPU_AES=0 "$WORK/gate" 2>&1); rc=$?
            if [ "$rc" -ne 0 ] && printf '%s' "$got" | grep -q 'needs AES-NI and PCLMULQDQ'; then
                ok "NURL_CPU_AES=0: an unasked call panics at the gate" "exit $rc"
            else
                bad "NURL_CPU_AES=0: an unasked call panics at the gate" "exit $rc: ${got:0:80}"
            fi
        else
            bad "NURL_CPU_AES=0: an unasked call panics at the gate" "could not build the probe"
        fi
    else
        note "runtime checks" "skipped (this CPU has no AES-NI / PCLMULQDQ)"
    fi
else
    note "machine-code and runtime checks" "skipped (no clang/objdump, or the link failed)"
fi

# ── 6. The runtime's answer matches an independent one ──────────────
if [ -r /proc/cpuinfo ] && command -v "$CLANG" >/dev/null 2>&1; then
    want=0
    if grep -qw aes /proc/cpuinfo && grep -qw pclmulqdq /proc/cpuinfo &&
            grep -qw ssse3 /proc/cpuinfo && grep -qw sse4_2 /proc/cpuinfo &&
            grep -qw popcnt /proc/cpuinfo; then
        want=1
    fi
    cat > "$WORK/cpu.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_aes(void);
int main(void) { printf("%d\n", nurl_cpu_x86_aes()); return 0; }
CEOF
    if "$CLANG" -O0 "$WORK/cpu.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu" 2>/dev/null)
        if [ "$got" = "$want" ]; then
            ok "runtime crypto-tier CPUID agrees with /proc/cpuinfo" "both say $want"
        else
            bad "runtime crypto-tier CPUID agrees with /proc/cpuinfo" \
                "runtime says $got, /proc/cpuinfo implies $want"
        fi
    else
        note "runtime CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
else
    note "runtime CPUID cross-check" "skipped (no /proc/cpuinfo)"
fi

# ── 7. The VAES tiers (v256, v512) ──────────────────────────────────
# simd_crypto_v256.nu / _v512.nu: the same contract one and two
# registers wider, plus what only a wide signature needs — the pointer
# crossing (emit_vabi): a tier function out of line in a caller without
# its tier hands its v256 / v512 over through memory, because the
# register it would travel in depends on each side's features.
TIER2='"target-cpu"="x86-64-v3" "target-features"="+avx,+avx2'
TIER3='"min-legal-vector-width"="512" "target-cpu"="x86-64-v4"'
for w in v256:2:encrypt2:round2:encrypt2x:nurl__vaes_gate v512:3:encrypt4:round4:encrypt4x:nurl__vaes512_gate; do
    IFS=: read -r ty lvl fn rnd sfn gate <<< "$w"
    src="$SCRIPT_DIR/simd_crypto_$ty.nu"
    want="$TIER2"; [ "$lvl" = 3 ] && want="$TIER3"
    "$NURLC" "$src" > "$WORK/$ty.ll" 2> "$WORK/$ty.err" || { bad "$ty: compiles" "$(head -2 "$WORK/$ty.err")"; continue; }
    "$NURLC" --no-cpu-dispatch "$src" > "$WORK/$ty.off.ll" 2>/dev/null || { bad "$ty: compiles off" "nurlc failed"; continue; }
    # The body under .vabi: tier attributes, gated, pointer parameters.
    vhdr=$(grep -E "^define void @__nurl_fn\.${fn}[a-z0-9_]*\.vabi\(i8\* %__vret, " "$WORK/$ty.ll" | head -1)
    case "$vhdr" in *"$want"*) ok "$fn.vabi: tier $lvl, $ty by pointer" "%__vret + .__vp" ;;
        *) bad "$fn.vabi: tier $lvl, $ty by pointer" "header: ${vhdr:0:140}" ;; esac
    vbody=$(awk -v h="$vhdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/$ty.ll")
    if printf '%s\n' "$vbody" | grep -q "call void @$gate()"; then ok "$fn.vabi: entry gated" "$gate"
    else bad "$fn.vabi: entry gated" "no $gate"; fi
    # The wrapper under the real name: the language signature, no
    # features, alwaysinline, spilling and calling the body.
    whdr=$(grep -E "^define <[48] x i64> @__nurl_fn\.${fn}[a-z0-9_]*\(" "$WORK/$ty.ll" | head -1)
    wbody=$(awk -v h="$whdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/$ty.ll")
    case "$whdr" in *target-features*) bad "$fn: featureless alwaysinline wrapper" "it carries features" ;;
        *alwaysinline*) if printf '%s\n' "$wbody" | grep -q "\.vabi(i8\* %__vret"; then
                ok "$fn: featureless alwaysinline wrapper" "spills, calls .vabi"
            else bad "$fn: featureless alwaysinline wrapper" "does not call the body by pointer"; fi ;;
        *) bad "$fn: featureless alwaysinline wrapper" "header: ${whdr:0:120}" ;; esac
    # A one-round helper: its .tier copy, which the simd function calls.
    thdr=$(grep -E "^define linkonce_odr <[48] x i64> @__nurl_fn\.${rnd}[a-z0-9_]*\.tier\(" "$WORK/$ty.ll" | head -1)
    case "$thdr" in *alwaysinline*"$want"*) ok "$rnd.tier: alwaysinline, tier $lvl" "linkonce_odr" ;;
        *) bad "$rnd.tier: alwaysinline, tier $lvl" "header: ${thdr:0:120}" ;; esac
    # The simd function reaches the tier through its helper: emitted
    # once, for the tier — no baseline clone, no v3 clone, no dispatcher.
    n_cl=$(grep -cE "^define .*@__nurl_fn\.${sfn}[a-z0-9_]*\.(base|x86v3)\(" "$WORK/$ty.ll")
    shdr=$(grep -E "^define void @__nurl_fn\.${sfn}[a-z0-9_]*\.vabi\(" "$WORK/$ty.ll" | head -1)
    sbody=$(awk -v h="$shdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/$ty.ll")
    if [ "$n_cl" -eq 0 ] && case "$shdr" in *"$want"*) true ;; *) false ;; esac &&
            printf '%s\n' "$sbody" | grep -qE "@__nurl_fn\.${rnd}[a-z0-9_]*\.tier\("; then
        ok "simd $sfn: one body for tier $lvl" "calls $rnd.tier"
    else
        bad "simd $sfn: one body for tier $lvl" "clones=$n_cl header: ${shdr:0:100}"
    fi
    # --no-cpu-dispatch: stubs and a constant false.
    has=nurl_cpu_has_vaes; miss=nurl_cpu_vaes_missing
    [ "$lvl" = 3 ] && { has=nurl_cpu_has_vaes512; miss=nurl_cpu_vaes512_missing; }
    if grep -A3 "^define linkonce_odr i1 @$has()" "$WORK/$ty.off.ll" | grep -q 'ret i1 false' &&
            grep -A3 "^define linkonce_odr <[48] x i64> @nurl_${ty}_aesenc(" "$WORK/$ty.off.ll" | grep -q "call void @$miss()" &&
            [ "$(grep -c 'llvm\.x86\.' "$WORK/$ty.off.ll")" -eq 0 ]; then
        ok "--no-cpu-dispatch: $has false, ${ty} primitives stubs" "$miss"
    else
        bad "--no-cpu-dispatch: $has false, ${ty} primitives stubs" "not so"
    fi
    # Machine code: the body really is VAES on ymm / zmm.
    reg=ymm; [ "$lvl" = 3 ] && reg=zmm
    if command -v "$CLANG" >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1 &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/$ty.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/$ty" -lm -lpthread 2>/dev/null; then
        n=$(objdump -d "$WORK/$ty" 2>/dev/null |
            awk -v f="$fn" '$0 ~ "^[0-9a-f]+ <[^>]*\\." f "[a-z0-9_]*\\.vabi>:"{p=1} /^$/{p=0} p' | grep -cE "vaesenc[a-z]* .*%$reg")
        if [ "$n" -gt 0 ]; then ok "$fn.vabi lowers to VAESENC on $reg" "$n"
        else bad "$fn.vabi lowers to VAESENC on $reg" "none"; fi
        env_off=NURL_CPU_VAES; [ "$lvl" = 3 ] && env_off=NURL_CPU_VAES512
        got=$(env "$env_off=0" "$WORK/$ty" 2>&1); rc=$?
        if [ "$rc" -eq 1 ] && printf '%s' "$got" | grep -q '^no .*tier on this CPU$'; then
            ok "$env_off=0: $has answers false" "software branch"
        else bad "$env_off=0: $has answers false" "exit $rc: ${got:0:80}"; fi
        sed 's/^    ? ! ( nurl_cpu_has_vaes[0-9]* ).*$//' "$src" > "$WORK/$ty.gate.nu"
        if "$NURLC" "$WORK/$ty.gate.nu" > "$WORK/$ty.gate.ll" 2>/dev/null &&
                "$CLANG" -O2 -flto -Wno-override-module "$WORK/$ty.gate.ll" "$ROOT/stdlib/runtime.o" \
                    -o "$WORK/$ty.gate" -lm -lpthread 2>/dev/null; then
            got=$(env "$env_off=0" "$WORK/$ty.gate" 2>&1); rc=$?
            if [ "$rc" -ne 0 ] && printf '%s' "$got" | grep -q 'needs .*VAES and VPCLMULQDQ'; then
                ok "$env_off=0: an unasked call panics at the gate" "exit $rc"
            else bad "$env_off=0: an unasked call panics at the gate" "exit $rc: ${got:0:80}"; fi
        else bad "$env_off=0: an unasked call panics at the gate" "could not build the probe"; fi
    else
        note "$ty machine-code and runtime checks" "skipped (no clang/objdump, or the link failed)"
    fi
done

# ── 8. A wide vector across a simd call, with each clone ────────────
# simd_wide_abi.nu proves the dispatcher and clones agree on where a
# v256 / v512 lives with the clone this CPU picks; here, with the wide
# clone taken away too.
if "$NURLC" "$SCRIPT_DIR/simd_wide_abi.nu" > "$WORK/abi.ll" 2>/dev/null &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/abi.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/abi" -lm -lpthread 2>/dev/null; then
    want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/simd_wide_abi.txt" | tail -n +2)
    a=$("$WORK/abi" 2>&1); b=$(NURL_CPU_V3=0 "$WORK/abi" 2>&1)
    if [ "$a" = "$want" ] && [ "$b" = "$want" ]; then ok "simd_wide_abi: both clones agree with the golden" "v3 and baseline"
    else bad "simd_wide_abi: both clones agree with the golden" "v3: ${a:0:40} / base: ${b:0:40}"; fi
else
    bad "simd_wide_abi: both clones agree with the golden" "could not build it"
fi

# ── 9. AES-GCM's kernels: each one built, and each one run ──────────
# aes_gcm_hw_agree.nu holds every kernel this CPU has to the software
# oracle; here the wide kernels must exist as VAES machine code, and
# the test must still agree with each wide tier taken away (the key
# for the missing tier then falls back a tier).
if "$NURLC" "$SCRIPT_DIR/aes_gcm_hw_agree.nu" > "$WORK/gcm.ll" 2>/dev/null &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/gcm.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/gcm" -lm -lpthread 2>/dev/null; then
    for k in "vaes_run:ymm" "vaes512_run:zmm"; do
        fnk=${k%%:*}; reg=${k##*:}
        n=$(objdump -d "$WORK/gcm" 2>/dev/null |
            awk -v f="$fnk" '$0 ~ "^[0-9a-f]+ <[^>]*__gcm_" f "[a-z0-9_]*>:"{p=1} /^$/{p=0} p' | grep -cE "vaesenc .*%$reg")
        if [ "$n" -gt 0 ]; then ok "__gcm_$fnk: VAESENC on $reg" "$n"
        else bad "__gcm_$fnk: VAESENC on $reg" "none"; fi
    done
    if grep -qw aes /proc/cpuinfo 2>/dev/null; then
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/aes_gcm_hw_agree.txt" | tail -n +2)
        for e in NURL_CPU_VAES512=0 NURL_CPU_VAES=0; do
            got=$(env "$e" "$WORK/gcm" 2>&1)
            if [ "$got" = "$want" ]; then ok "aes_gcm_hw_agree with $e" "golden"
            else bad "aes_gcm_hw_agree with $e" "${got:0:80}"; fi
        done
    fi
else
    bad "aes_gcm_hw_agree: builds" "nurlc or the link failed"
fi

# ── 10. The runtime's wide answers match an independent one ─────────
if [ -r /proc/cpuinfo ] && command -v "$CLANG" >/dev/null 2>&1; then
    fl=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    has() { for f in "$@"; do case "$fl" in *" $f "*) ;; *) return 1 ;; esac; done; }
    w2=0; w3=0
    has aes pclmulqdq avx2 bmi2 fma vaes vpclmulqdq && w2=1
    [ "$w2" = 1 ] && has avx512f avx512bw avx512cd avx512dq avx512vl && w3=1
    cat > "$WORK/cpu2.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_vaes(void);
int nurl_cpu_x86_vaes512(void);
int main(void) { printf("%d %d\n", nurl_cpu_x86_vaes(), nurl_cpu_x86_vaes512()); return 0; }
CEOF
    if "$CLANG" -O0 "$WORK/cpu2.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu2" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu2" 2>/dev/null)
        if [ "$got" = "$w2 $w3" ]; then ok "runtime VAES / AVX-512 VAES CPUID agrees with /proc/cpuinfo" "both say $got"
        else bad "runtime VAES / AVX-512 VAES CPUID agrees with /proc/cpuinfo" "runtime $got, /proc/cpuinfo $w2 $w3"; fi
    else
        note "runtime wide CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "crypto_tier_ir: all assertions passed"
    exit 0
fi
echo "crypto_tier_ir: $fails assertion(s) FAILED"
exit 1
