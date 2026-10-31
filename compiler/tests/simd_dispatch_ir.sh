#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/simd_dispatch_ir.sh — the `simd` prefix, checked at
#  the level a behavioural test cannot see.
#
#  simd_dispatch.nu proves a marked function computes the right answer.
#  It CANNOT prove which clone ran, that there are two of them, or that
#  the wide one carries feature bits the baseline one does not — and
#  those are the whole feature. This checks the IR, and then checks the
#  machine code, so a change that silently stops emitting the wide clone
#  fails here instead of quietly costing 1.7x on the PQ stack.
#
#  Every assertion greps for a POSITIVE marker and counts it. A gate
#  that only looks for the absence of an error passes just as happily
#  when nothing ran at all.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/simd_dispatch.nu"

[ -x "$NURLC" ] || { echo "simd_dispatch_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }
[ -f "$SRC" ] || { echo "simd_dispatch_ir: $SRC missing" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

note() { printf '  %-52s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }
ok() { note "$1" "ok ($2)"; }

# The five functions simd_dispatch.nu marks. `__sum`, `__triple`-caller
# and `tri` are file-private, so they reach the IR under a mangled name
# — match on the stem and let the suffix be whatever privacy produced.
MARKED='__sum|scale_into|dot|sum_tripled|tri'

cd "$ROOT" || exit 2
# --cpu-dispatch: these are IR checks of the prefix itself, so they ask
# for it explicitly — on a non-x86-64 host nurlc starts with it off.
"$NURLC" --cpu-dispatch "$SRC" > "$WORK/on.ll" 2> "$WORK/on.err" || {
    echo "simd_dispatch_ir: nurlc failed"; cat "$WORK/on.err"; exit 1; }
"$NURLC" --no-cpu-dispatch "$SRC" > "$WORK/off.ll" 2> "$WORK/off.err" || {
    echo "simd_dispatch_ir: nurlc --no-cpu-dispatch failed"; cat "$WORK/off.err"; exit 1; }

# ── 1. Both clones exist, and only the wide one carries features ────
n_base=$(grep -cE "^define .*@__nurl_fn\.($MARKED)[a-z0-9_]*\.base\(" "$WORK/on.ll")
n_wide=$(grep -cE "^define .*@__nurl_fn\.($MARKED)[a-z0-9_]*\.x86v3\(" "$WORK/on.ll")
if [ "$n_base" -ge 5 ] && [ "$n_base" -eq "$n_wide" ]; then
    ok "baseline and wide clones pair up" "$n_base each"
else
    bad "baseline and wide clones pair up" "base=$n_base wide=$n_wide (want >=5, equal)"
fi

n_feat=$(grep -cE '^define .*\.x86v3\(.*"target-features"="\+avx,\+avx2,' "$WORK/on.ll")
if [ "$n_feat" -eq "$n_wide" ] && [ "$n_feat" -gt 0 ]; then
    ok "every wide clone carries the AVX2 feature set" "$n_feat"
else
    bad "every wide clone carries the AVX2 feature set" "$n_feat of $n_wide"
fi

n_leak=$(grep -cE '^define .*\.base\(.*target-features' "$WORK/on.ll")
if [ "$n_leak" -eq 0 ]; then
    ok "no baseline clone carries feature bits" "0"
else
    bad "no baseline clone carries feature bits" "$n_leak did"
fi

# ── 2. A dispatcher under the real name, calling both ───────────────
n_disp=$(grep -c 'call i32 @nurl_cpu_x86_v3()' "$WORK/on.ll")
if [ "$n_disp" -eq "$n_wide" ] && [ "$n_disp" -gt 0 ]; then
    ok "one CPUID dispatcher per marked function" "$n_disp"
else
    bad "one CPUID dispatcher per marked function" "$n_disp vs $n_wide clones"
fi

for lbl in __mv_wide __mv_base; do
    n=$(grep -c "^$lbl:" "$WORK/on.ll")
    if [ "$n" -eq "$n_disp" ]; then ok "dispatcher has a $lbl arm" "$n"
    else bad "dispatcher has a $lbl arm" "$n vs $n_disp"; fi
done

# The dispatcher must be reachable under the UNDECORATED name, or every
# caller in the program silently kept calling something else.
if grep -qE "^define i64 @__nurl_fn\.__sum[a-z0-9_]*\(i8\* %p, i64 %n\) \{" "$WORK/on.ll"; then
    ok "dispatcher owns the undecorated symbol" "__sum"
else
    bad "dispatcher owns the undecorated symbol" "no plain @__sum define"
fi

# ── 3. --no-cpu-dispatch really emits ONE copy ──────────────────────
n_off=$(grep -cE "^define .*(\.base|\.x86v3)\(" "$WORK/off.ll")
n_off_disp=$(grep -c 'call i32 @nurl_cpu_x86_v3()' "$WORK/off.ll")
if [ "$n_off" -eq 0 ] && [ "$n_off_disp" -eq 0 ]; then
    ok "--no-cpu-dispatch emits no clones" "0 clones, 0 dispatchers"
else
    bad "--no-cpu-dispatch emits no clones" "$n_off clones, $n_off_disp dispatchers"
fi
n_off_fn=$(grep -cE "^define .*@__nurl_fn\.($MARKED)[a-z0-9_]*\(" "$WORK/off.ll")
if [ "$n_off_fn" -ge 5 ]; then
    ok "--no-cpu-dispatch still defines the functions" "$n_off_fn"
else
    bad "--no-cpu-dispatch still defines the functions" "only $n_off_fn"
fi

# ── 4. --g suppresses cloning (a DISubprogram binds to one function) ─
"$NURLC" --cpu-dispatch --g "$SRC" > "$WORK/g.ll" 2>/dev/null
n_g=$(grep -cE "^define .*(\.base|\.x86v3)\(" "$WORK/g.ll")
if [ "$n_g" -eq 0 ]; then
    ok "--g suppresses cloning" "0 clones"
else
    bad "--g suppresses cloning" "$n_g clones — !dbg would be attached twice"
fi

# ── 5. A marked module is not partitioned ───────────────────────────
rm -f "$WORK"/sp.*.ll
"$NURLC" --cpu-dispatch --split=8 --split-out="$WORK/sp" "$SRC" > /dev/null 2>&1
n_parts=$(ls "$WORK"/sp.*.ll 2>/dev/null | wc -l)
if [ "$n_parts" -eq 0 ]; then
    ok "marked module declines to split" "0 parts"
else
    bad "marked module declines to split" "$n_parts parts — the wide clone loses its callees"
fi

# ── 6. The wide clone really contains AVX2 in the object code ───────
# The feature attribute is a request; this is the answer. Skipped when
# the host toolchain cannot lower x86-64 (the check is about codegen,
# not about this machine's CPU — a cross-capable clang still emits it).
if command -v clang >/dev/null 2>&1 && command -v objdump >/dev/null 2>&1; then
    if clang -O2 -c -Wno-override-module --target=x86_64-unknown-linux-gnu \
            "$WORK/on.ll" -o "$WORK/on.o" 2>/dev/null; then
        wide_ymm=$(objdump -d "$WORK/on.o" 2>/dev/null |
            awk '/^[0-9a-f]+ <[^>]*\.x86v3>:/{p=1} /^$/{p=0} p' | grep -c 'ymm')
        base_ymm=$(objdump -d "$WORK/on.o" 2>/dev/null |
            awk '/^[0-9a-f]+ <[^>]*\.base>:/{p=1} /^$/{p=0} p' | grep -c 'ymm')
        if [ "$wide_ymm" -gt 0 ] && [ "$base_ymm" -eq 0 ]; then
            ok "wide clones use ymm, baseline clones do not" "$wide_ymm vs $base_ymm"
        else
            bad "wide clones use ymm, baseline clones do not" "wide=$wide_ymm base=$base_ymm"
        fi
    else
        note "object-code check" "skipped (clang cannot target x86-64 here)"
    fi
else
    note "object-code check" "skipped (no clang/objdump)"
fi

# ── 7. The runtime's answer matches an independent one ──────────────
# Everything above checks that the wide clone was BUILT. Nothing above
# notices nurl_cpu_x86_v3() answering 0 forever: the program still runs,
# still passes every vector, and is silently 1.7x slower. So ask the
# kernel what the CPU has and require the runtime to agree.
#
# This is not a check that the host has AVX2 — it is a check that the
# runtime and /proc/cpuinfo tell the same story, which is a claim that
# holds on a machine without it too.
if [ -r /proc/cpuinfo ] && [ "$(uname -m)" = "x86_64" ] &&
        command -v clang >/dev/null 2>&1; then
    want=0
    if grep -qm1 ' avx2 ' /proc/cpuinfo && grep -qm1 ' bmi2 ' /proc/cpuinfo &&
            grep -qm1 ' fma ' /proc/cpuinfo; then
        want=1
    fi
    cat > "$WORK/cpu.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_v3(void);
int main(void) { printf("%d\n", nurl_cpu_x86_v3()); return 0; }
CEOF
    if clang -O0 "$WORK/cpu.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu" 2>/dev/null)
        if [ "$got" = "$want" ]; then
            ok "runtime CPUID agrees with /proc/cpuinfo" "both say $want"
        else
            bad "runtime CPUID agrees with /proc/cpuinfo" \
                "runtime says $got, /proc/cpuinfo implies $want"
        fi
    else
        note "runtime CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
else
    note "runtime CPUID cross-check" "skipped (not x86-64 Linux)"
fi

# ── 8. A program's own CPUID question is lowered as declared ─────────
# std/chacha20poly1305.nu asks `# i ( nurl_cpu_x86_v3 )` itself before
# taking a wide path. The preamble declares the function `i32`; a call
# lowered `call i64` ran on x86 (eax read as rax) but trapped a wasm
# module on the signature mismatch, and wasmbuilder's fold of
# `call i32 @nurl_cpu_x86_v3()` to 0 never matched it (wasm-bench:
# poly1305 printed nothing).
cat > "$WORK/ask.nu" <<'NEOF'
@ wide_ok i len → b {
    ^ & >= len 256 != 0 # i ( nurl_cpu_x86_v3 )
}
@ main → i {
    ( nurl_println_int # i ( wide_ok 300 ) )
    ^ 0
}
NEOF
if "$NURLC" "$WORK/ask.nu" > "$WORK/ask.ll" 2> "$WORK/ask.err"; then
    n_i32=$(grep -cE '= call i32 @nurl_cpu_x86_v3\(\)' "$WORK/ask.ll")
    n_bad=$(grep -E 'call [^ ]+ @nurl_cpu_x86_v3\(' "$WORK/ask.ll" | grep -vc 'call i32 @')
    if [ "$n_i32" -gt 0 ] && [ "$n_bad" -eq 0 ]; then
        ok "a program's nurl_cpu_x86_v3 call is i32" "$n_i32"
    else
        bad "a program's nurl_cpu_x86_v3 call is i32" "$n_i32 i32, $n_bad other"
    fi
else
    bad "a program's nurl_cpu_x86_v3 call is i32" "nurlc failed: $(head -1 "$WORK/ask.err")"
fi

# ── 8b. A clone answers its body's own CPUID question ───────────────
# `.x86v3` runs only where the dispatcher's probe said 1 and `.base`
# only where it said 0, so each folds the body's call to that constant
# and LLVM drops the path it never takes (the eight-block v256 pass in
# __chacha20_xor_wide's `.base`). A crypto `.base` also runs on a v3 CPU
# without the tier, so it keeps the call; the dispatcher always asks.
cat > "$WORK/fold.nu" <<'NEOF'
simd @ pick i n → i {
    ? != 0 # i ( nurl_cpu_x86_v3 ) { ^ + n 1 } {}
    ^ n
}
simd @ pick_aes v128 k v128 x → v128 {
    ? != 0 # i ( nurl_cpu_x86_v3 ) { ^ ( nurl_v128_aesenc x k ) } {}
    ^ ( nurl_v128_aesenclast x k )
}
@ main → i {
    ( nurl_println_int ( pick 1 ) )
    : v128 c ( pick_aes ( nurl_v128_bcast32 1 ) ( nurl_v128_bcast32 2 ) )
    ^ 0
}
NEOF
if "$NURLC" --cpu-dispatch "$WORK/fold.nu" > "$WORK/fold.ll" 2> "$WORK/fold.err"; then
    fn_ir() { awk -v f="$1" 'index($0, "define") == 1 && index($0, f) { p = 1 } p { print } p && /^}/ { exit }' "$WORK/fold.ll"; }
    w=$(fn_ir 'pick.x86v3(' | grep -c 'add i32 0, 1')
    b=$(fn_ir 'pick.base(' | grep -c 'add i32 0, 0')
    left=$( { fn_ir 'pick.x86v3('; fn_ir 'pick.base('; } | grep -c '@nurl_cpu_x86_v3()')
    d=$(fn_ir 'pick(' | grep -c 'call i32 @nurl_cpu_x86_v3()')
    cw=$(fn_ir 'pick_aes.x86v3(' | grep -c 'call i32 @nurl_cpu_x86_v3()')
    cb=$(fn_ir 'pick_aes.base(' | grep -c 'call i32 @nurl_cpu_x86_v3()')
    if [ "$w" -eq 1 ] && [ "$b" -eq 1 ] && [ "$left" -eq 0 ] && [ "$d" -eq 1 ] && [ "$cw" -eq 0 ] && [ "$cb" -eq 1 ]; then
        ok "each clone answers its own nurl_cpu_x86_v3" "x86v3 1, base 0, crypto base asks"
    else
        bad "each clone answers its own nurl_cpu_x86_v3" "x86v3=$w base=$b unfolded=$left dispatcher=$d crypto x86v3 call=$cw crypto base call=$cb"
    fi
else
    bad "each clone answers its own nurl_cpu_x86_v3" "nurlc failed: $(head -1 "$WORK/fold.err")"
fi

# ── The v256 lowering ChaCha20-Poly1305 depends on ────────────────────
# Two things LLVM gets wrong from the obvious IR, each worth a tenth or
# more of the AEAD, invisible to any behavioural test:
#   * a 32×32 → 64 lane multiply (nurl_v256_mul32u) whose operand's high
#     bits the backend cannot see — a loop-carried value, or a broadcast
#     whose mask the optimiser moved out of the loop — is lowered as THREE
#     multiplies and two 32-bit shifts instead of one `vpmuludq`; the
#     four-block Poly1305 (__poly_wide) is written so that never happens;
#   * a rotate by 8 or 16 spelled as a funnel shift is reassociated across
#     ChaCha20's xor into a third byte shuffle per quarter-round pair
#     (nurl_v256_rotl32 spells it as a byte permutation instead): the
#     eight-block round must have one `vpshufb` per two `vpxor`.
if [ "$(uname -m)" = "x86_64" ] && command -v objdump >/dev/null 2>&1 &&
        "$NURLC" "$SCRIPT_DIR/chacha20poly1305_sweep.nu" > "$WORK/ccp.ll" 2>/dev/null &&
        clang -O2 -flto -Wno-override-module "$WORK/ccp.ll" "$ROOT/stdlib/runtime.o" \
            -o "$WORK/ccp" -lm -lpthread 2>/dev/null; then
    objdump -d --no-show-raw-insn "$WORK/ccp" > "$WORK/ccp.s" 2>/dev/null
    pw=$(awk '/^[0-9a-f]+ <[^>]*__poly_wide[a-z0-9_]*\.x86v3>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s")
    n_mul=$(printf '%s\n' "$pw" | grep -c 'vpmuludq')
    n_x32=$(printf '%s\n' "$pw" | grep -cE 'vps(ll|rl)q[[:space:]]+\$0x20')
    if [ "$n_mul" -gt 0 ] && [ "$n_x32" -eq 0 ]; then
        ok "__poly_wide: one vpmuludq a product" "$n_mul vpmuludq, no 32-bit split"
    else
        bad "__poly_wide: one vpmuludq a product" "$n_mul vpmuludq, $n_x32 split shifts"
    fi
    # Its baseline clone never runs (callers ask __poly_wide_ok, and the
    # kernel asks v3 itself), so it folds to `ret 0`: no multiply left in
    # the binary (the LTO link usually inlines the clone away entirely).
    n_bb=$(awk '/^[0-9a-f]+ <[^>]*__poly_wide[a-z0-9_]*\.base>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -c 'pmuludq')
    if [ "$n_bb" -eq 0 ]; then
        ok "__poly_wide: the baseline clone does no arithmetic" "no pmuludq in its code"
    else
        bad "__poly_wide: the baseline clone does no arithmetic" "$n_bb pmuludq in its code"
    fi
    cw=$(awk '/^[0-9a-f]+ <[^>]*__chacha20_xor_wide[a-z0-9_]*\.x86v3>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s")
    n_sh=$(printf '%s\n' "$cw" | grep -cE 'vpshufb[[:space:]].*%ymm')
    n_xo=$(printf '%s\n' "$cw" | grep -cE 'vpxor[[:space:]].*%ymm')
    if [ "$n_sh" -gt 0 ] && [ $((2 * n_sh)) -le "$n_xo" ]; then
        ok "chacha20 eight-block round: vpshufb ≤ vpxor / 2" "$n_sh vpshufb, $n_xo vpxor"
    else
        bad "chacha20 eight-block round: vpshufb ≤ vpxor / 2" "$n_sh vpshufb, $n_xo vpxor"
    fi
else
    note "ChaCha20-Poly1305 v256 lowering" "skipped (not x86-64, or no objdump / build)"
fi

# ── 9. `simd v4`: the third clone (grammar v2.12) ────────────────────
# simd_v4_dispatch.nu marks two functions `simd v4`. Each gets an
# `.x86v4` clone compiled for x86-64-v4, beside its `.base` / `.x86v3`,
# and a dispatcher that asks nurl_cpu_x86_v4 first. The v4 clone must
# really be AVX-512 code (VPROLD on the rotates), ChaCha20's wide pass
# too, the golden must hold with the third clone taken away
# (NURL_CPU_V4=0), the CPU probes a clone's dispatcher already answered
# must be constants inside it, and the runtime's v4 answer must agree
# with /proc/cpuinfo.
V4SRC="$SCRIPT_DIR/simd_v4_dispatch.nu"
if "$NURLC" --cpu-dispatch "$V4SRC" > "$WORK/v4.ll" 2> "$WORK/v4.err"; then
    n4=$(grep -cE '^define .*@__nurl_fn\.(mix|twice)[a-z0-9_]*\.x86v4\(.*"target-cpu"="x86-64-v4".*\+avx512vl' "$WORK/v4.ll")
    n3=$(grep -cE '^define .*@__nurl_fn\.(mix|twice)[a-z0-9_]*\.x86v3\(' "$WORK/v4.ll")
    nb=$(grep -cE '^define .*@__nurl_fn\.(mix|twice)[a-z0-9_]*\.base\(' "$WORK/v4.ll")
    if [ "$n4" -eq 2 ] && [ "$n3" -eq 2 ] && [ "$nb" -eq 2 ]; then
        ok "simd v4: base, x86v3 and x86-64-v4 clones" "2 of each"
    else
        bad "simd v4: base, x86v3 and x86-64-v4 clones" "base=$nb v3=$n3 v4=$n4 (want 2 each)"
    fi
    nq=$(grep -c '%__mv4r = call i32 @nurl_cpu_x86_v4()' "$WORK/v4.ll")
    if [ "$nq" -eq 3 ]; then ok "simd v4: each dispatcher asks nurl_cpu_x86_v4" "$nq"
    else bad "simd v4: each dispatcher asks nurl_cpu_x86_v4" "$nq calls (want 3)"; fi
    # Inside a clone, the probes its dispatcher answered are constants:
    # `level` asks none in any of its three clones, while plain-`simd`
    # `level3` still asks v4 in its `.x86v3` (which a v4 CPU runs) and
    # nothing in its `.base`.
    probes() {  # probes <fn> <clone>: CPU probe calls left in that body
        awk -v f="$1" -v c="$2" '$0 ~ "^define .*@__nurl_fn\\." f "(__fp[0-9]+)?\\." c "\\(" {p=1} p && /^}/ {p=0} p' "$WORK/v4.ll" |
            grep -oE 'call i32 @nurl_cpu_x86_v[34]\(\)' | sed -E 's/.*_(v[34]).*/\1/' | sort | paste -sd, -
    }
    # Off x86-64 both probes answer 0 on every CPU, and are compiled as
    # that constant in every function; an x86-64 module built without
    # clones still asks.
    if "$NURLC" --target=aarch64 "$V4SRC" > "$WORK/v4a64.ll" 2>/dev/null &&
            "$NURLC" --no-cpu-dispatch "$V4SRC" > "$WORK/v4nd.ll" 2>/dev/null; then
        na=$(grep -c 'call i32 @nurl_cpu_x86_v[34]()' "$WORK/v4a64.ll")
        nn=$(grep -c 'call i32 @nurl_cpu_x86_v[34]()' "$WORK/v4nd.ll")
        if [ "$na" -eq 0 ] && [ "$nn" -gt 0 ]; then
            ok "x86 level probes: constant 0 off x86-64, calls without clones" "aarch64 0, --no-cpu-dispatch $nn"
        else
            bad "x86 level probes: constant 0 off x86-64, calls without clones" "aarch64 $na (want 0), --no-cpu-dispatch $nn (want > 0)"
        fi
    else
        bad "simd_v4_dispatch: compiles for aarch64 and without dispatch" "nurlc failed"
    fi
    pf="$(probes level base)/$(probes level x86v3)/$(probes level x86v4)/$(probes level3 base)/$(probes level3 x86v3)"
    if [ "$pf" = "////v4" ]; then ok "simd clones fold the probes their dispatcher answered" "only level3.x86v3 asks v4"
    else bad "simd clones fold the probes their dispatcher answered" "left: $pf (want ////v4)"; fi
    # A plain `simd` function asks no v4 question.
    n0=$(grep -c 'nurl_cpu_x86_v4()' "$WORK/on.ll" | tr -d ' ')
    nd=$(grep -c '^declare i32  @nurl_cpu_x86_v4()' "$WORK/on.ll" | tr -d ' ')
    if [ $((n0 - nd)) -eq 0 ]; then ok "plain simd: no v4 dispatch" "0 calls"
    else bad "plain simd: no v4 dispatch" "$((n0 - nd)) calls"; fi
    if [ "$(uname -m)" = "x86_64" ] && command -v objdump >/dev/null 2>&1 &&
            clang -O2 -flto -Wno-override-module "$WORK/v4.ll" "$ROOT/stdlib/runtime.o" \
                -o "$WORK/v4" -lm -lpthread 2>/dev/null; then
        objdump -d --no-show-raw-insn "$WORK/v4" > "$WORK/v4.s" 2>/dev/null
        r4=$(awk '/^[0-9a-f]+ <[^>]*__nurl_fn\.mix[a-z0-9_]*\.x86v4>:/{p=1} /^$/{p=0} p' "$WORK/v4.s" | grep -c 'vprold')
        r3=$(awk '/^[0-9a-f]+ <[^>]*__nurl_fn\.mix[a-z0-9_]*\.x86v3>:/{p=1} /^$/{p=0} p' "$WORK/v4.s" | grep -c 'vprold')
        if [ "$r4" -gt 0 ] && [ "$r3" -eq 0 ]; then ok "simd v4: VPROLD in the v4 clone only" "$r4 vs $r3"
        else bad "simd v4: VPROLD in the v4 clone only" "v4=$r4 v3=$r3"; fi
        want=$(sed -n '/^OUTPUT$/,$p' "$SCRIPT_DIR/outputs/simd_v4_dispatch.txt" | tail -n +2)
        for e in "NURL_CPU_V4=1" "NURL_CPU_V4=0" "NURL_CPU_V3=0"; do
            got=$(env $e "$WORK/v4" 2>&1)
            if [ "$got" = "$want" ]; then ok "simd_v4_dispatch with $e" "golden"
            else bad "simd_v4_dispatch with $e" "${got:0:80}"; fi
        done
        if [ -f "$WORK/ccp.s" ]; then
            c4=$(awk '/^[0-9a-f]+ <[^>]*__chacha20_xor_wide[a-z0-9_]*\.x86v4>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -c 'vprold')
            if [ "$c4" -gt 0 ]; then ok "__chacha20_xor_wide: an x86-64-v4 clone with VPROLD" "$c4"
            else bad "__chacha20_xor_wide: an x86-64-v4 clone with VPROLD" "none"; fi
            # The sixteen-block pass (Agora #116) is zmm code in the v4
            # clone, and only there: the other clones fold its
            # nurl_cpu_x86_v4 guard to 0 and drop it.
            z4=$(awk '/^[0-9a-f]+ <[^>]*__chacha20_xor_wide[a-z0-9_]*\.x86v4>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -cE 'vprold[[:space:]].*%zmm')
            zs=$(awk '/^[0-9a-f]+ <[^>]*__chacha20_xor_wide[a-z0-9_]*\.x86v4>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -c 'vshufi64x2')
            zo=$(awk '/^[0-9a-f]+ <[^>]*__chacha20_xor_wide[a-z0-9_]*\.(x86v3|base)>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -c '%zmm')
            if [ "$z4" -gt 0 ] && [ "$zs" -gt 0 ] && [ "$zo" -eq 0 ]; then
                ok "chacha20 sixteen-block pass: zmm in the v4 clone only" "$z4 VPROLD zmm, $zs VSHUFI64X2; 0 zmm elsewhere"
            else
                bad "chacha20 sixteen-block pass: zmm in the v4 clone only" "v4: $z4 VPROLD zmm, $zs VSHUFI64X2; other clones: $zo zmm"
            fi
            # Eight-lane Poly1305 (Agora #116) is the same: zmm VPMULUDQ
            # in __poly_wide's v4 clone, one a product (no 32-bit split),
            # and no zmm in its other clones.
            pz=$(awk '/^[0-9a-f]+ <[^>]*__poly_wide[a-z0-9_]*\.x86v4>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s")
            pm4=$(printf '%s\n' "$pz" | grep -cE 'vpmuludq[[:space:]].*%zmm')
            px4=$(printf '%s\n' "$pz" | grep -cE 'vps(ll|rl)q[[:space:]]+\$0x20')
            po=$(awk '/^[0-9a-f]+ <[^>]*__poly_wide[a-z0-9_]*\.(x86v3|base)>:/{p=1} /^$/{p=0} p' "$WORK/ccp.s" | grep -c '%zmm')
            if [ "$pm4" -gt 0 ] && [ "$px4" -eq 0 ] && [ "$po" -eq 0 ]; then
                ok "poly1305 eight-lane pass: zmm in the v4 clone only" "$pm4 VPMULUDQ zmm, no 32-bit split; 0 zmm elsewhere"
            else
                bad "poly1305 eight-lane pass: zmm in the v4 clone only" "v4: $pm4 VPMULUDQ zmm, $px4 split shifts; other clones: $po zmm"
            fi
        fi
    else
        note "simd v4 machine code and run" "skipped (not x86-64, or no objdump / build)"
    fi
else
    bad "simd_v4_dispatch: compiles" "$(head -2 "$WORK/v4.err")"
fi
if [ -r /proc/cpuinfo ] && [ "$(uname -m)" = "x86_64" ] && command -v clang >/dev/null 2>&1; then
    want4=0
    fl=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    have=1
    for f in avx2 bmi2 fma avx512f avx512bw avx512cd avx512dq avx512vl; do
        case "$fl" in *" $f "*) ;; *) have=0 ;; esac
    done
    want4=$have
    cat > "$WORK/cpu4.c" <<'CEOF'
#include <stdio.h>
int nurl_cpu_x86_v4(void);
int main(void) { printf("%d\n", nurl_cpu_x86_v4()); return 0; }
CEOF
    if clang -O0 "$WORK/cpu4.c" "$ROOT/stdlib/runtime.native.o" -o "$WORK/cpu4" \
            -lm -lpthread -ldl -lsqlite3 2>/dev/null; then
        got=$("$WORK/cpu4" 2>/dev/null)
        off=$(NURL_CPU_V4=0 "$WORK/cpu4" 2>/dev/null)
        if [ "$got" = "$want4" ] && [ "$off" = 0 ]; then
            ok "runtime x86-64-v4 CPUID agrees with /proc/cpuinfo" "both say $got; NURL_CPU_V4=0 → 0"
        else
            bad "runtime x86-64-v4 CPUID agrees with /proc/cpuinfo" "runtime $got (masked $off), /proc/cpuinfo $want4"
        fi
    else
        note "runtime x86-64-v4 CPUID cross-check" "skipped (could not link runtime.native.o)"
    fi
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "simd_dispatch_ir: all assertions passed"
    exit 0
fi
echo "simd_dispatch_ir: $fails assertion(s) FAILED"
exit 1
