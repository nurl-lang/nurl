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
#  (emit_vabi). Then AES-GCM's wide kernels must exist as VAES machine
#  code and agree with the software oracle with each tier taken away.
#  Last, the SHA tier (nurl_v128_sha256*), which is on no chain with the
#  AES ones: a body using both is compiled, gated and dispatched on both,
#  and SHA-256's kernel is SHA256RNDS2 code that agrees with the
#  portable rounds.
#
#  First, on every host, the AArch64 lowering of the AES tier (section
#  A): its IR and machine code, and — natively on an AArch64 host, or
#  under qemu-aarch64 where there is one — simd_crypto, aes_gcm_hw_agree
#  and aes_gcm_vectors against the goldens the x86 lowering is held to.
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

note() { printf '  %-56s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }
ok() { note "$1" "ok ($2)"; }

CLANG="${CLANG:-clang}"
HOST_ARCH="$(uname -m)"
cd "$ROOT" || exit 2

# ── A. The AArch64 lowering (any host) ──────────────────────────────
# `--target=aarch64`: the same primitives on the ARMv8 Cryptographic
# Extension — AESE / AESD with a zero key then AESMC / AESIMC and the
# round key XORed after (Intel's round order), PMULL / PMULL2 on the
# selected halves — under the same contract: a tier function compiled
# with `+aes` and gated on nurl_cpu_arm_aes, its `.tier` copy what other
# tier code calls, a `simd` function that reaches the tier emitted once
# for it (there are no x86 clones on AArch64). Checked in the IR and the
# machine code on every host; run natively on an AArch64 one, and under
# qemu-aarch64 on an x86-64 one that has it and an aarch64 sysroot —
# against the same goldens the x86 lowering is held to.
a64_checks() {
    local A64='"target-features"="+neon,+aes"'
    "$NURLC" --target=aarch64 "$SRC" > "$WORK/a64.ll" 2> "$WORK/a64.err" || {
        bad "aarch64: simd_crypto compiles" "$(head -2 "$WORK/a64.err")"; return; }
    local n_x86
    n_x86=$(grep -c 'llvm\.x86\.' "$WORK/a64.ll")
    if [ "$n_x86" -eq 0 ] && grep -q 'llvm\.aarch64\.crypto\.aese' "$WORK/a64.ll" &&
            grep -q 'llvm\.aarch64\.neon\.pmull64' "$WORK/a64.ll"; then
        ok "aarch64: AESE / PMULL intrinsics, no x86 ones" "0 llvm.x86"
    else
        bad "aarch64: AESE / PMULL intrinsics, no x86 ones" "$n_x86 llvm.x86"
    fi
    local hdr body
    hdr=$(grep -E '^define .*@__nurl_fn\.next_key[a-z0-9_]*\(' "$WORK/a64.ll" | head -1)
    body=$(awk -v h="$hdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/a64.ll")
    case "$hdr" in *noinline*"$A64"*) ok "aarch64: next_key compiled for the tier" "+neon,+aes, noinline" ;;
        *) bad "aarch64: next_key compiled for the tier" "header: ${hdr:0:120}" ;; esac
    if printf '%s\n' "$body" | grep -q 'call void @nurl__aes_gate()' &&
            grep -A3 '^define linkonce_odr void @nurl__aes_gate()' "$WORK/a64.ll" | grep -q '@nurl_cpu_arm_aes()'; then
        ok "aarch64: gated on nurl_cpu_arm_aes" "nurl__aes_gate"
    else
        bad "aarch64: gated on nurl_cpu_arm_aes" "no gate, or the gate asks something else"
    fi
    local n_cl ehdr ebody
    n_cl=$(grep -cE '^define .*@__nurl_fn\.encrypt[a-z0-9_]*\.(base|x86v3)\(' "$WORK/a64.ll")
    ehdr=$(grep -E '^define .*@__nurl_fn\.encrypt[a-z0-9_]*\(' "$WORK/a64.ll" | head -1)
    ebody=$(awk -v h="$ehdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/a64.ll")
    if [ "$n_cl" -eq 0 ] && case "$ehdr" in *"$A64"*) true ;; *) false ;; esac &&
            printf '%s\n' "$ebody" | grep -qE '@__nurl_fn\.aes_round[a-z0-9_]*\.tier\(' &&
            printf '%s\n' "$ebody" | grep -q 'call void @nurl__aes_gate()'; then
        ok "aarch64: simd encrypt is one gated tier body" "calls aes_round.tier"
    else
        bad "aarch64: simd encrypt is one gated tier body" "clones=$n_cl header: ${ehdr:0:100}"
    fi
    # (Unreferenced preamble functions are dropped: ask for all of it.)
    "$NURLC" --target=aarch64 --no-dce "$SRC" > "$WORK/a64.all.ll" 2>/dev/null
    if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_vaes()' "$WORK/a64.all.ll" | grep -q 'ret i1 false' &&
            grep -A3 '^define linkonce_odr <4 x i64> @nurl_v256_aesenc(' "$WORK/a64.all.ll" | grep -q 'call void @nurl_cpu_vaes_missing()'; then
        ok "aarch64: no VAES tier" "has_vaes false, v256 primitives stubs"
    else
        bad "aarch64: no VAES tier" "nurl_cpu_has_vaes or nurl_v256_aesenc is not the stub"
    fi
    # Machine code. The round key must have moved into the AESE (LLVM
    # folds `aese(x ^ k, 0)`): the ARM-shaped sequence, not one EOR a
    # round beside a zero-keyed AESE.
    local cross=""
    case "$HOST_ARCH" in aarch64|arm64) ;; *) cross="--target=aarch64-linux-gnu" ;; esac
    local OBJDUMP=""
    if command -v llvm-objdump >/dev/null 2>&1; then OBJDUMP=llvm-objdump
    elif [ -z "$cross" ] && command -v objdump >/dev/null 2>&1; then OBJDUMP=objdump; fi
    # shellcheck disable=SC2086
    if [ -n "$OBJDUMP" ] && "$CLANG" $cross -O2 -Wno-override-module -c "$WORK/a64.ll" -o "$WORK/a64.o" 2>"$WORK/a64.cerr"; then
        local dis n_aese n_mc n_eor n_pm
        dis=$("$OBJDUMP" -d "$WORK/a64.o" 2>/dev/null |
            awk '/^[0-9a-f]+ <[^>]*encrypt[a-z0-9_]*>:/{p=1} /^$/{p=0} p')
        n_aese=$(printf '%s\n' "$dis" | grep -cE '\baese\b')
        n_mc=$(printf '%s\n' "$dis" | grep -cE '\baesmc\b')
        n_eor=$(printf '%s\n' "$dis" | grep -cE '\beor\b')
        if [ "$n_aese" -gt 0 ] && [ "$n_mc" -gt 0 ] && [ "$n_eor" -lt "$n_aese" ]; then
            ok "aarch64: encrypt lowers to AESE + AESMC, keys folded" "$n_aese aese, $n_mc aesmc, $n_eor eor"
        else
            bad "aarch64: encrypt lowers to AESE + AESMC, keys folded" "$n_aese aese, $n_mc aesmc, $n_eor eor"
        fi
        n_pm=$("$OBJDUMP" -d "$WORK/a64.o" 2>/dev/null | grep -cE '\bpmull2?\b')
        if [ "$n_pm" -gt 0 ]; then ok "aarch64: the products lower to PMULL" "$n_pm"
        else bad "aarch64: the products lower to PMULL" "none"; fi
    else
        note "aarch64 machine-code checks" "skipped (no aarch64-capable clang / objdump)"
    fi
    # Run it: natively, or under qemu-aarch64.
    local runner="" link_ok=0 qemu=""
    case "$HOST_ARCH" in
        aarch64|arm64)
            if "$CLANG" -O2 -flto -Wno-override-module "$WORK/a64.ll" "$ROOT/stdlib/runtime.o" \
                    -o "$WORK/a64" -lm -lpthread 2>/dev/null; then link_ok=1; fi ;;
        *)
            for q in qemu-aarch64-static qemu-aarch64; do
                command -v "$q" >/dev/null 2>&1 && { qemu="$q"; break; }
            done
            local sys="${NURL_A64_SYSROOT:-/usr/aarch64-linux-gnu}"
            if [ -n "$qemu" ] && [ -d "$sys/lib" ] && command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 &&
                    "$CLANG" --target=aarch64-linux-gnu --sysroot="$sys" -O2 -c "$ROOT/stdlib/runtime.c" \
                        -o "$WORK/rt64.o" 2>/dev/null; then
                runner="$qemu -cpu max -L $sys"
                a64_link() {  # a64_link <ll> <out>
                    "$CLANG" --target=aarch64-linux-gnu -O2 -Wno-override-module -c "$1" -o "$1.o" 2>/dev/null &&
                        aarch64-linux-gnu-gcc "$1.o" "$WORK/rt64.o" -o "$2" -lm -lpthread -ldl 2>/dev/null
                }
                a64_link "$WORK/a64.ll" "$WORK/a64" && link_ok=1
            fi ;;
    esac
    if [ "$link_ok" -ne 1 ]; then
        note "aarch64 runtime checks" "skipped (not an AArch64 host, and no qemu-aarch64 + aarch64 sysroot)"
        return
    fi
    local want got rc
    want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/simd_crypto.txt" | tail -n +2)
    # shellcheck disable=SC2086
    got=$($runner "$WORK/a64" 2>&1)
    if [ "$got" = "$want" ]; then ok "aarch64: simd_crypto agrees with the x86 golden" "${runner:+under qemu-aarch64}${runner:-natively}"
    else bad "aarch64: simd_crypto agrees with the x86 golden" "${got:0:80}"; fi
    # shellcheck disable=SC2086
    got=$(NURL_CPU_AES=0 $runner "$WORK/a64" 2>&1); rc=$?
    if [ "$rc" -eq 1 ] && [ "$got" = "no crypto tier on this CPU" ]; then
        ok "aarch64 NURL_CPU_AES=0: nurl_cpu_has_aes answers false" "software branch"
    else bad "aarch64 NURL_CPU_AES=0: nurl_cpu_has_aes answers false" "exit $rc: ${got:0:80}"; fi
    # And a program that does not ask reaches the gate: a panic naming
    # the ARM extension, not SIGILL.
    sed 's/^    ? ! ( nurl_cpu_has_aes ).*$//' "$SRC" > "$WORK/a64gate.nu"
    if "$NURLC" --target=aarch64 "$WORK/a64gate.nu" > "$WORK/a64gate.ll" 2>/dev/null &&
            if [ -n "$runner" ]; then a64_link "$WORK/a64gate.ll" "$WORK/a64gate"
            else "$CLANG" -O2 -flto -Wno-override-module "$WORK/a64gate.ll" "$ROOT/stdlib/runtime.o" \
                    -o "$WORK/a64gate" -lm -lpthread 2>/dev/null; fi; then
        # shellcheck disable=SC2086
        got=$(NURL_CPU_AES=0 $runner "$WORK/a64gate" 2>&1); rc=$?
        if [ "$rc" -ne 0 ] && printf '%s' "$got" | grep -q 'ARMv8 Cryptographic Extension'; then
            ok "aarch64 NURL_CPU_AES=0: an unasked call panics at the gate" "exit $rc"
        else bad "aarch64 NURL_CPU_AES=0: an unasked call panics at the gate" "exit $rc: ${got:0:80}"; fi
    else
        bad "aarch64 NURL_CPU_AES=0: an unasked call panics at the gate" "could not build the probe"
    fi
    # AES-GCM's eight-block kernel on the ARM instructions, against the
    # software oracle and the NIST vectors — the goldens x86 is held to.
    local t
    for t in aes_gcm_hw_agree aes_gcm_vectors; do
        if "$NURLC" --target=aarch64 "$SCRIPT_DIR/$t.nu" > "$WORK/$t.ll" 2>/dev/null &&
                if [ -n "$runner" ]; then a64_link "$WORK/$t.ll" "$WORK/$t"
                else "$CLANG" -O2 -flto -Wno-override-module "$WORK/$t.ll" "$ROOT/stdlib/runtime.o" \
                        -o "$WORK/$t" -lm -lpthread 2>/dev/null; fi; then
            want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/$t.txt" | tail -n +2)
            # shellcheck disable=SC2086
            got=$(cd "$SCRIPT_DIR" && $runner "$WORK/$t" 2>&1)
            if [ "$got" = "$want" ]; then ok "aarch64: $t agrees with its golden" "hardware path"
            else bad "aarch64: $t agrees with its golden" "${got:0:80}"; fi
        else
            bad "aarch64: $t builds" "nurlc or the link failed"
        fi
    done
}
a64_checks

# The x86 tiers are x86-64 feature sets: on any other host the rest has
# nothing to run — the AArch64 checks above were the ones for it.
case "$HOST_ARCH" in
    x86_64|amd64) ;;
    *)
        echo ""
        if [ "$fails" -eq 0 ]; then
            echo "crypto_tier_ir: AArch64 assertions passed ($HOST_ARCH host: no x86 tiers to check)"
            exit 0
        fi
        echo "crypto_tier_ir: $fails assertion(s) FAILED"
        exit 1 ;;
esac

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
    # A gated entry is only called from outside the tier (callers inside
    # it take the `.tier` copy), so it must stay a call: noinline, never
    # alwaysinline or inlinehint — a toolchain that optimises for the host
    # CPU and generates code for the baseline (zig cc's ThinLTO) merged it
    # into a baseline caller, and instruction selection failed.
    case "$hdr" in *alwaysinline*|*inlinehint*) bad "$fn: stays a call" "inlinable: ${hdr:0:120}" ;;
        *noinline*) ok "$fn: stays a call" "noinline" ;;
        *) bad "$fn: stays a call" "no noinline" ;; esac
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
# `two_rounds` wraps aes_round without a primitive of its own: it gets a
# `.tier` copy too, calling aes_round's, and the clones call that copy.
whdr=$(grep -E "^define linkonce_odr .*@__nurl_fn\.two_rounds[a-z0-9_]*\.tier\(" "$WORK/on.ll" | head -1)
if [ -n "$whdr" ]; then
    case "$whdr" in *alwaysinline*"$TIER"*) ok "two_rounds.tier: wrapper copy, tier attributes" "linkonce_odr" ;;
        *) bad "two_rounds.tier: wrapper copy, tier attributes" "header: ${whdr:0:120}" ;; esac
    wbody=$(awk -v h="$whdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
    n=$(printf '%s\n' "$wbody" | grep -cE '@__nurl_fn\.aes_round[a-z0-9_]*\.tier\(')
    if [ "$n" -eq 2 ]; then ok "two_rounds.tier calls aes_round.tier" "$n calls"
    else bad "two_rounds.tier calls aes_round.tier" "$n of 2 calls"; fi
else
    bad "two_rounds.tier: exists" "no linkonce_odr .tier define"
fi
for clone in base x86v3; do
    chdr=$(grep -E "^define .*@__nurl_fn\.encrypt[a-z0-9_]*\.${clone}\(" "$WORK/on.ll" | head -1)
    cbody=$(awk -v h="$chdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/on.ll")
    if printf '%s\n' "$cbody" | grep -qE '@__nurl_fn\.two_rounds[a-z0-9_]*\.tier\('; then
        ok "encrypt.$clone calls two_rounds.tier" "wrapper inlined ungated"
    else
        bad "encrypt.$clone calls two_rounds.tier" "it calls something else"
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
for h in base:"$bhdr" x86v3:"$whdr"; do
    case "${h#*:}" in *noinline*) ok "encrypt.${h%%:*}: stays a call from the dispatcher" "noinline" ;;
        *) bad "encrypt.${h%%:*}: stays a call from the dispatcher" "no noinline" ;; esac
done
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
            awk -v f="$fn" '$0 ~ "^[0-9a-f]+ <[^>]*\\." f "[a-z0-9_]*\\.vabi>:"{p=1} /^$/{p=0} p' | grep -cE "vaesenc[a-z]*[[:space:]].*%$reg")
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
            awk -v f="$fnk" '$0 ~ "^[0-9a-f]+ <[^>]*__gcm_" f "[a-z0-9_]*>:"{p=1} /^$/{p=0} p' | grep -cE "vaesenc[[:space:]].*%$reg")
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

# ── 11. The SHA tier: not on the AES chain ─────────────────────────
# nurl_v128_sha256* (x86 SHA extensions). The tier is x86-64-v2 + SHA,
# incomparable with the AES tiers: a function that uses both kinds of
# primitive is compiled for, gated on and dispatched on BOTH, and a
# SHA-only function carries no AES. SHA-256's kernel must be SHA256RNDS2
# machine code, and its golden must hold on both of SHA-256's paths.
SHA_SRC="$SCRIPT_DIR/sha256_tier_agree.nu"
if "$NURLC" "$SHA_SRC" > "$WORK/sha.ll" 2> "$WORK/sha.err"; then
    nhdr=$(grep -E '^define .*@__nurl_fn\.__sha256_blocks_ni[a-z0-9_]*\(' "$WORK/sha.ll" | head -1)
    nbody=$(awk -v h="$nhdr" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/sha.ll")
    case "$nhdr" in
        *noinline*'"target-cpu"="x86-64-v2" "target-features"="+cx16,+popcnt,+sse3,+sse4.1,+sse4.2,+ssse3,+sha"'*)
            ok "__sha256_blocks_ni: x86-64-v2 + SHA, no AES" "noinline" ;;
        *) bad "__sha256_blocks_ni: x86-64-v2 + SHA, no AES" "header: ${nhdr:0:160}" ;;
    esac
    if printf '%s\n' "$nbody" | grep -q 'call void @nurl__sha_gate()' &&
            ! printf '%s\n' "$nbody" | grep -q 'nurl__aes_gate' &&
            grep -A3 '^define linkonce_odr void @nurl__sha_gate()' "$WORK/sha.ll" | grep -q '@nurl_cpu_x86_sha()'; then
        ok "__sha256_blocks_ni: gated on nurl_cpu_x86_sha alone" "nurl__sha_gate"
    else
        bad "__sha256_blocks_ni: gated on nurl_cpu_x86_sha alone" "no SHA gate, or an AES one"
    fi
    if command -v "$CLANG" >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1 &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/sha.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/sha" -lm -lpthread 2>/dev/null; then
        n=$(objdump -d "$WORK/sha" 2>/dev/null |
            awk '/^[0-9a-f]+ <[^>]*__sha256_blocks_ni[a-z0-9_]*>:/{p=1} /^$/{p=0} p' | grep -cE '\bsha256rnds2\b')
        if [ "$n" -eq 32 ]; then ok "__sha256_blocks_ni: 32 SHA256RNDS2 a block" "$n"
        else bad "__sha256_blocks_ni: 32 SHA256RNDS2 a block" "$n"; fi
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/sha256_tier_agree.txt" | tail -n +2)
        for e in NURL_CPU_SHA=1 NURL_CPU_SHA=0; do
            got=$(env "$e" "$WORK/sha" 2>&1)
            if [ "$got" = "$want" ]; then ok "sha256_tier_agree with $e" "golden"
            else bad "sha256_tier_agree with $e" "${got:0:80}"; fi
        done
    else
        note "SHA-256 machine code and run" "skipped (no clang / objdump, or the link failed)"
    fi
else
    bad "sha256_tier_agree: compiles" "$(head -2 "$WORK/sha.err")"
fi

# Both tiers in one `simd` body: the union, everywhere it matters.
cat > "$WORK/mix.nu" <<'NEOF'
$ `stdlib/core/vec.nu`
unsafe simd @ mix * u p → v {
    : v128 a ( nurl_v128_ld # s p )
    : v128 b ( nurl_v128_aesenc a a )
    ( nurl_v128_st # s p ( nurl_v128_sha256msg1 b a ) )
}
unsafe @ main → i {
    : ( Vec u ) v ( vec_zeroed [u] 16 )
    ( mix ( vec_data [u] v ) )
    ^ 0
}
NEOF
if "$NURLC" "$WORK/mix.nu" > "$WORK/mix.ll" 2> "$WORK/mix.err"; then
    mb=$(grep -E '^define .*@__nurl_fn\.mix[a-z0-9_]*\.base\(' "$WORK/mix.ll" | head -1)
    mw=$(grep -E '^define .*@__nurl_fn\.mix[a-z0-9_]*\.x86v3\(' "$WORK/mix.ll" | head -1)
    md=$(grep -E '^define .*@__nurl_fn\.mix[a-z0-9_]*\(i8\* %p\) \{' "$WORK/mix.ll" | head -1)
    case "$mb" in *'"target-features"="+aes,+pclmul,+cx16,+popcnt,+sse3,+sse4.1,+sse4.2,+ssse3,+sha"'*)
            ok "AES + SHA simd body: .base has both" "+aes,+pclmul … +sha" ;;
        *) bad "AES + SHA simd body: .base has both" "header: ${mb:0:160}" ;; esac
    case "$mw" in *'"target-cpu"="x86-64-v3"'*'+aes,+pclmul,+sha"'*)
            ok "AES + SHA simd body: .x86v3 has both" "v3 +aes,+pclmul,+sha" ;;
        *) bad "AES + SHA simd body: .x86v3 has both" "header: ${mw:0:160}" ;; esac
    mbb=$(awk -v h="$mb" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/mix.ll")
    mdb=$(awk -v h="$md" '$0==h{p=1;next} p&&/^}/{exit} p' "$WORK/mix.ll")
    if printf '%s\n' "$mbb" | grep -q 'call void @nurl__aes_gate()' &&
            printf '%s\n' "$mbb" | grep -q 'call void @nurl__sha_gate()'; then
        ok "AES + SHA simd body: .base gated on both" "two gates"
    else
        bad "AES + SHA simd body: .base gated on both" "a gate is missing"
    fi
    if printf '%s\n' "$mdb" | grep -q 'call i32 @nurl_cpu_x86_v3()' &&
            printf '%s\n' "$mdb" | grep -q 'call i32 @nurl_cpu_x86_aes()' &&
            printf '%s\n' "$mdb" | grep -q 'call i32 @nurl_cpu_x86_sha()'; then
        ok "AES + SHA dispatcher: wide only with v3, AES and SHA" "three probes"
    else
        bad "AES + SHA dispatcher: wide only with v3, AES and SHA" "missing a probe"
    fi
    if grep -qw sha_ni /proc/cpuinfo 2>/dev/null && grep -qw aes /proc/cpuinfo 2>/dev/null &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/mix.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/mix" -lm -lpthread 2>/dev/null; then
        "$WORK/mix" >/dev/null 2>&1; rc_on=$?
        got=$(NURL_CPU_SHA=0 "$WORK/mix" 2>&1); rc_off=$?
        if [ "$rc_on" -eq 0 ] && [ "$rc_off" -ne 0 ] && printf '%s' "$got" | grep -q 'needs the SHA extensions'; then
            ok "AES + SHA body without SHA: the gate panics" "exit $rc_off"
        else
            bad "AES + SHA body without SHA: the gate panics" "on=$rc_on off=$rc_off ${got:0:60}"
        fi
    fi
else
    bad "AES + SHA simd body: compiles" "$(head -2 "$WORK/mix.err")"
fi

# Outside x86 there is no SHA tier (yet): a constant false and stubs.
"$NURLC" --no-cpu-dispatch --no-dce "$WORK/mix.nu" > "$WORK/mix.off.ll" 2>/dev/null
"$NURLC" --target=aarch64 --no-dce "$WORK/mix.nu" > "$WORK/mix.a64.ll" 2>/dev/null
for f in off a64; do
    if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_sha()' "$WORK/mix.$f.ll" | grep -q 'ret i1 false' &&
            grep -A3 '^define linkonce_odr <4 x i32> @nurl_v128_sha256rnds2(' "$WORK/mix.$f.ll" | grep -q 'call void @nurl_cpu_sha_missing()' &&
            [ "$(grep -c 'llvm\.x86\.sha' "$WORK/mix.$f.ll")" -eq 0 ]; then
        ok "$f: nurl_cpu_has_sha false, SHA primitives stubs" "nurl_cpu_sha_missing"
    else
        bad "$f: nurl_cpu_has_sha false, SHA primitives stubs" "not so"
    fi
done

# The runtime's SHA answer matches an independent one.
if [ -r /proc/cpuinfo ] && command -v "$CLANG" >/dev/null 2>&1; then
    fl=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    ws=1
    # (SSE3 is `pni` there.)
    for f in pni ssse3 cx16 sse4_1 sse4_2 popcnt sha_ni; do
        case "$fl" in *" $f "*) ;; *) ws=0 ;; esac
    done
    cat > "$WORK/cpu3.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_sha(void);
int main(void) { printf("%d\n", nurl_cpu_x86_sha()); return 0; }
CEOF
    if "$CLANG" -O0 "$WORK/cpu3.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu3" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu3" 2>/dev/null)
        off=$(NURL_CPU_SHA=0 "$WORK/cpu3" 2>/dev/null)
        if [ "$got" = "$ws" ] && [ "$off" = 0 ]; then ok "runtime SHA CPUID agrees with /proc/cpuinfo" "both say $got; NURL_CPU_SHA=0 → 0"
        else bad "runtime SHA CPUID agrees with /proc/cpuinfo" "runtime $got (off: $off), /proc/cpuinfo $ws"; fi
    else
        note "runtime SHA CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
fi

# ── 12. The ADX tier: nurl_mac_row's two carry chains ───────────────
# A row of a multi-precision multiply (rp[0..n) += ap[0..n)·b) on mulx,
# adcx and adox where the runtime says BMI2 + ADX, the portable loop
# elsewhere. The asm must be there on x86-64 (LLVM never selects ADOX on
# its own), absent off x86, and both paths must hold the same golden —
# the primitive's own (every width 0 … 40) and std/rsa_mont's, whose
# Montgomery multiply takes the row form on the ADX tier and FIPS
# without it.
MR_SRC="$SCRIPT_DIR/mac_row_agree.nu"
if "$NURLC" "$MR_SRC" > "$WORK/mr.ll" 2> "$WORK/mr.err"; then
    if grep -A8 '^define linkonce_odr i64 @nurl_mac_row(' "$WORK/mr.ll" | grep -q 'call i1 @nurl_cpu_has_adx()' &&
            grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_adx()' "$WORK/mr.ll" | grep -q '@nurl_cpu_x86_adx()'; then
        ok "nurl_mac_row: dispatched on nurl_cpu_x86_adx" "nurl_cpu_has_adx"
    else
        bad "nurl_mac_row: dispatched on nurl_cpu_x86_adx" "no ADX probe in the row"
    fi
    if command -v "$CLANG" >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1 &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/mr.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/mr" -lm -lpthread 2>/dev/null; then
        # GNU objdump prints adcx / adox, llvm-objdump (FreeBSD's objdump)
        # the AT&T-suffixed adcxq / adoxq
        nx=$(objdump -d "$WORK/mr" 2>/dev/null | grep -cE '\badoxq?\b')
        nc=$(objdump -d "$WORK/mr" 2>/dev/null | grep -cE '\badcxq?\b')
        # two call sites, each 1 + 4 + 8 product adds and 1 carry fold
        if [ "$nx" -eq 28 ] && [ "$nc" -eq 28 ]; then ok "mac_row_agree: two inlined rows of ADCX / ADOX" "$nc adcx, $nx adox"
        else bad "mac_row_agree: two inlined rows of ADCX / ADOX" "$nc adcx, $nx adox"; fi
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/mac_row_agree.txt" | tail -n +2)
        for e in NURL_CPU_ADX=1 NURL_CPU_ADX=0; do
            got=$(env "$e" "$WORK/mr" 2>&1)
            if [ "$got" = "$want" ]; then ok "mac_row_agree with $e" "golden"
            else bad "mac_row_agree with $e" "${got:0:80}"; fi
        done
    else
        note "nurl_mac_row machine code and run" "skipped (no clang / objdump, or the link failed)"
    fi
else
    bad "mac_row_agree: compiles" "$(head -2 "$WORK/mr.err")"
fi

RK_SRC="$SCRIPT_DIR/rsa_mont_kernels.nu"
if "$NURLC" "$RK_SRC" > "$WORK/rk.ll" 2> "$WORK/rk.err" &&
        command -v "$CLANG" >/dev/null 2>&1 &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/rk.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/rk" -lm -lpthread 2>/dev/null; then
    want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/rsa_mont_kernels.txt" | tail -n +2)
    for e in NURL_CPU_ADX=1 NURL_CPU_ADX=0; do
        got=$(env "$e" "$WORK/rk" 2>&1)
        if [ "$got" = "$want" ]; then ok "rsa_mont_kernels with $e" "golden"
        else bad "rsa_mont_kernels with $e" "${got:0:80}"; fi
    done
else
    bad "rsa_mont_kernels: builds" "$(head -2 "$WORK/rk.err")"
fi

# RSA-2048's halves take the runtime's straight-line ADX blocks
# (nurl_rsa16_sqrm_adx / nurl_rsa16_mulm_adx, tools/gen_rsa_adx16.py) on
# this tier and std/rsa_mont's FIPS kernels without it: both must hold
# rsa16_kernel_agree's golden (every product checked against std/bigint,
# edge-shaped moduli and operands), and the linked program must carry the
# blocks' ADCX / ADOX — straight-line, no branch inside them.
R16_SRC="$SCRIPT_DIR/rsa16_kernel_agree.nu"
if "$NURLC" "$R16_SRC" > "$WORK/r16.ll" 2> "$WORK/r16.err" &&
        command -v "$CLANG" >/dev/null 2>&1 &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/r16.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/r16" -lm -lpthread 2>/dev/null; then
    want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/rsa16_kernel_agree.txt" | tail -n +2)
    for e in NURL_CPU_ADX=1 NURL_CPU_ADX=0; do
        got=$(env "$e" "$WORK/r16" 2>&1)
        if [ "$got" = "$want" ]; then ok "rsa16_kernel_agree with $e" "golden"
        else bad "rsa16_kernel_agree with $e" "${got:0:80}"; fi
    done
    if command -v objdump >/dev/null 2>&1; then
        sq=$(objdump -d "$WORK/r16" 2>/dev/null | awk '/<nurl_rsa16_sqrm_adx>:/,/^$/')
        nsq=$(printf '%s\n' "$sq" | grep -cE '\badcxq?\b')
        if [ "$nsq" -gt 400 ]; then ok "nurl_rsa16_sqrm_adx: linked, ADCX chains" "$nsq adcx"
        else bad "nurl_rsa16_sqrm_adx: linked, ADCX chains" "$nsq adcx"; fi
    else
        note "nurl_rsa16_sqrm_adx machine code" "skipped (no objdump)"
    fi
else
    bad "rsa16_kernel_agree: builds" "$(head -2 "$WORK/r16.err")"
fi

# Off x86 there is no ADX tier: a constant false and no asm.
"$NURLC" --no-cpu-dispatch --no-dce "$MR_SRC" > "$WORK/mr.off.ll" 2>/dev/null
"$NURLC" --target=aarch64 --no-dce "$MR_SRC" > "$WORK/mr.a64.ll" 2>/dev/null
for f in off a64; do
    if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_adx()' "$WORK/mr.$f.ll" | grep -q 'ret i1 false' &&
            grep -q '^define linkonce_odr i64 @nurl_mac_row(' "$WORK/mr.$f.ll" &&
            [ "$(grep -c 'adox' "$WORK/mr.$f.ll")" -eq 0 ]; then
        ok "$f: nurl_cpu_has_adx false, nurl_mac_row portable" "no asm"
    else
        bad "$f: nurl_cpu_has_adx false, nurl_mac_row portable" "not so"
    fi
done

# The runtime's ADX answer matches an independent one.
if [ -r /proc/cpuinfo ] && command -v "$CLANG" >/dev/null 2>&1; then
    fl=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    wa=1
    for f in bmi2 adx; do
        case "$fl" in *" $f "*) ;; *) wa=0 ;; esac
    done
    cat > "$WORK/cpu4.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_adx(void);
int main(void) { printf("%d\n", nurl_cpu_x86_adx()); return 0; }
CEOF
    if "$CLANG" -O0 "$WORK/cpu4.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu4" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu4" 2>/dev/null)
        off=$(NURL_CPU_ADX=0 "$WORK/cpu4" 2>/dev/null)
        if [ "$got" = "$wa" ] && [ "$off" = 0 ]; then ok "runtime ADX CPUID agrees with /proc/cpuinfo" "both say $got; NURL_CPU_ADX=0 → 0"
        else bad "runtime ADX CPUID agrees with /proc/cpuinfo" "runtime $got (off: $off), /proc/cpuinfo $wa"; fi
    else
        note "runtime ADX CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
fi

# ── 12b. The field kernels on the ADX tier: X25519 and P-256 ────────
# nurl_x25519_mulm / _sqrm (mulx, adcx, adox where the runtime says
# BMI2 + ADX, else F: the register form) and nurl_p256_mulm / _sqrm (the
# same tier, else mulq) are asm blocks the compiler emits on x86-64 and a
# constant F off it. Each agreement test holds the kernels — and the
# ladders written on them — to the register form, so both settings of
# the tier must give its golden.
for fk in x25519_kernel_agrees p256_kernel_agrees; do
    if "$NURLC" "$SCRIPT_DIR/$fk.nu" > "$WORK/$fk.ll" 2> "$WORK/$fk.err" &&
            command -v "$CLANG" >/dev/null 2>&1 &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/$fk.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/$fk" -lm -lpthread 2>/dev/null; then
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/$fk.txt" | tail -n +2)
        for e in NURL_CPU_ADX=1 NURL_CPU_ADX=0; do
            got=$(env "$e" "$WORK/$fk" 2>&1)
            if [ "$got" = "$want" ]; then ok "$fk with $e" "golden"
            else bad "$fk with $e" "${got:0:80}"; fi
        done
    else
        bad "$fk: builds" "$(head -2 "$WORK/$fk.err")"
    fi
done
if grep -A4 '^define linkonce_odr i1 @nurl_x25519_mulm(' "$WORK/x25519_kernel_agrees.ll" | grep -q 'call i1 @nurl_cpu_has_adx()' &&
        grep -A4 '^define linkonce_odr i1 @nurl_x25519_sqrm(' "$WORK/x25519_kernel_agrees.ll" | grep -q 'call i1 @nurl_cpu_has_adx()'; then
    ok "nurl_x25519_mulm / _sqrm: dispatched on nurl_cpu_has_adx" "both"
else
    bad "nurl_x25519_mulm / _sqrm: dispatched on nurl_cpu_has_adx" "no ADX probe"
fi
if command -v objdump >/dev/null 2>&1 && [ -x "$WORK/x25519_kernel_agrees" ]; then
    nx=$(objdump -d "$WORK/x25519_kernel_agrees" 2>/dev/null | grep -cE '\badoxq?\b')
    nc=$(objdump -d "$WORK/x25519_kernel_agrees" 2>/dev/null | grep -cE '\badcxq?\b')
    if [ "$nx" -gt 0 ] && [ "$nc" -gt 0 ]; then ok "x25519_kernel_agrees: ADCX / ADOX in the machine code" "$nc adcx, $nx adox"
    else bad "x25519_kernel_agrees: ADCX / ADOX in the machine code" "$nc adcx, $nx adox"; fi
fi
"$NURLC" --target=aarch64 --no-dce "$SCRIPT_DIR/x25519_kernel_agrees.nu" > "$WORK/fkx.a64.ll" 2>/dev/null
if grep -A3 '^define linkonce_odr i1 @nurl_x25519_mulm(' "$WORK/fkx.a64.ll" | grep -q 'ret i1 false' &&
        grep -A3 '^define linkonce_odr i1 @nurl_x25519_sqrm(' "$WORK/fkx.a64.ll" | grep -q 'ret i1 false' &&
        [ "$(grep -c 'adox\|mulx' "$WORK/fkx.a64.ll")" -eq 0 ]; then
    ok "a64: nurl_x25519_mulm / _sqrm a constant F" "no asm"
else
    bad "a64: nurl_x25519_mulm / _sqrm a constant F" "not so"
fi

# ── 13. The IFMA tier: both RSA CRT halves at once, radix 2^52 ───────
# nurl_v256_madd52lo / _hi on x86-64-v4 + AVX-512 IFMA, gated like the
# AES tiers. std/rsa_mont's __rm_pow2_52 is a `simd` function written
# with inline helpers of inline helpers; it must be ONE body of the tier
# (the helpers' .tier copies inlined, ungated) — not baseline clones
# calling each helper's gated original by pointer, which ran a
# signature at 4.1 ms instead of ~0.27. Both paths hold the goldens of
# rsa_pow2_agree (_rm_pow2_ct against bigint_modpow) and rsa_pss_sign
# (a CRT key end to end).
P2_SRC="$SCRIPT_DIR/rsa_pow2_agree.nu"
if "$NURLC" "$P2_SRC" > "$WORK/p2.ll" 2> "$WORK/p2.err"; then
    if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_ifma()' "$WORK/p2.ll" | grep -q '@nurl_cpu_x86_ifma()' &&
            grep -A3 '^define linkonce_odr void @nurl__ifma_gate()' "$WORK/p2.ll" | grep -q '@nurl_cpu_x86_ifma()'; then
        ok "IFMA probe and gate ask nurl_cpu_x86_ifma" "probe"
    else
        bad "IFMA probe and gate ask nurl_cpu_x86_ifma" "no probe"
    fi
    pw=$(grep '^define.*@__nurl_fn\.__rm_pow2_52[^(]*(' "$WORK/p2.ll")
    pb=$(awk '/^define.*@__nurl_fn\.__rm_pow2_52[^(.]*\(/{p=1} p{print} /^}/{p=0}' "$WORK/p2.ll")
    if [ "$(printf '%s\n' "$pw" | grep -c .)" -eq 1 ] &&
            printf '%s\n' "$pw" | grep -q '+avx512ifma' &&
            printf '%s\n' "$pb" | grep -q 'call void @nurl__ifma_gate()' &&
            ! printf '%s\n' "$pb" | grep -q '@__nurl_fn\.__rm_a52lo[^.(]*(' ; then
        ok "__rm_pow2_52: one IFMA body, helpers inlined ungated" "+avx512ifma, gated"
    else
        bad "__rm_pow2_52: one IFMA body, helpers inlined ungated" "$(printf '%s\n' "$pw" | grep -c .) definitions"
    fi
    if command -v "$CLANG" >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1 &&
            "$CLANG" -O2 -flto -Wno-override-module "$WORK/p2.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/p2" -lm -lpthread 2>/dev/null; then
        nl=$(objdump -d "$WORK/p2" 2>/dev/null | grep -cE '\bvpmadd52luq\b')
        nh=$(objdump -d "$WORK/p2" 2>/dev/null | grep -cE '\bvpmadd52huq\b')
        # nine inlined AMMs, each 2 halves × 5 blocks × 2 (a·b, m·y)
        if [ "$nl" -eq 180 ] && [ "$nh" -eq 180 ]; then ok "__rm_pow2_52: nine inlined AMMs of VPMADD52" "$nl lo, $nh hi"
        else bad "__rm_pow2_52: nine inlined AMMs of VPMADD52" "$nl lo, $nh hi"; fi
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/rsa_pow2_agree.txt" | tail -n +2)
        for e in NURL_CPU_IFMA=1 NURL_CPU_IFMA=0; do
            got=$(env "$e" "$WORK/p2" 2>&1)
            if [ "$got" = "$want" ]; then ok "rsa_pow2_agree with $e" "golden"
            else bad "rsa_pow2_agree with $e" "${got:0:80}"; fi
        done
    else
        note "IFMA machine code and run" "skipped (no clang / objdump, or the link failed)"
    fi
else
    bad "rsa_pow2_agree: compiles" "$(head -2 "$WORK/p2.err")"
fi

PS_SRC="$SCRIPT_DIR/rsa_pss_sign.nu"
if "$NURLC" "$PS_SRC" > "$WORK/ps.ll" 2> "$WORK/ps.err" &&
        command -v "$CLANG" >/dev/null 2>&1 &&
        "$CLANG" -O2 -flto -Wno-override-module "$WORK/ps.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/ps" -lm -lpthread 2>/dev/null; then
    want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/rsa_pss_sign.txt" | tail -n +2)
    for e in NURL_CPU_IFMA=1 NURL_CPU_IFMA=0; do
        got=$(env "$e" "$WORK/ps" 2>&1)
        if [ "$got" = "$want" ]; then ok "rsa_pss_sign with $e" "golden"
        else bad "rsa_pss_sign with $e" "${got:0:80}"; fi
    done
else
    bad "rsa_pss_sign: builds" "$(head -2 "$WORK/ps.err")"
fi

# Off x86 there is no IFMA tier: a constant false and panicking stubs.
"$NURLC" --no-cpu-dispatch --no-dce "$P2_SRC" > "$WORK/p2.off.ll" 2>/dev/null
"$NURLC" --target=aarch64 --no-dce "$P2_SRC" > "$WORK/p2.a64.ll" 2>/dev/null
for f in off a64; do
    if grep -A3 '^define linkonce_odr i1 @nurl_cpu_has_ifma()' "$WORK/p2.$f.ll" | grep -q 'ret i1 false' &&
            grep -A3 '^define linkonce_odr <4 x i64> @nurl_v256_madd52lo(' "$WORK/p2.$f.ll" | grep -q 'nurl_cpu_ifma_missing' &&
            [ "$(grep -c 'avx512ifma\|vpmadd52' "$WORK/p2.$f.ll")" -eq 0 ]; then
        ok "$f: nurl_cpu_has_ifma false, IFMA primitives stubs" "nurl_cpu_ifma_missing"
    else
        bad "$f: nurl_cpu_has_ifma false, IFMA primitives stubs" "not so"
    fi
done

# The runtime's IFMA answer matches an independent one.
if [ -r /proc/cpuinfo ] && command -v "$CLANG" >/dev/null 2>&1; then
    fl=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    wi=1
    for f in avx2 avx512f avx512bw avx512cd avx512dq avx512vl avx512ifma; do
        case "$fl" in *" $f "*) ;; *) wi=0 ;; esac
    done
    cat > "$WORK/cpu5.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_ifma(void);
int main(void) { printf("%d\n", nurl_cpu_x86_ifma()); return 0; }
CEOF
    if "$CLANG" -O0 "$WORK/cpu5.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu5" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu5" 2>/dev/null)
        off=$(NURL_CPU_IFMA=0 "$WORK/cpu5" 2>/dev/null)
        if [ "$got" = "$wi" ] && [ "$off" = 0 ]; then ok "runtime IFMA CPUID agrees with /proc/cpuinfo" "both say $got; NURL_CPU_IFMA=0 → 0"
        else bad "runtime IFMA CPUID agrees with /proc/cpuinfo" "runtime $got (off: $off), /proc/cpuinfo $wi"; fi
    else
        note "runtime IFMA CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "crypto_tier_ir: all assertions passed"
    exit 0
fi
echo "crypto_tier_ir: $fails assertion(s) FAILED"
exit 1
