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
NURLC="$ROOT/build/nurlc"
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
"$NURLC" "$SRC" > "$WORK/on.ll" 2> "$WORK/on.err" || {
    echo "simd_dispatch_ir: nurlc failed"; cat "$WORK/on.err"; exit 1; }
"$NURLC" --no-cpu-dispatch "$SRC" > "$WORK/off.ll" 2> "$WORK/off.err" || {
    echo "simd_dispatch_ir: nurlc --no-cpu-dispatch failed"; cat "$WORK/off.err"; exit 1; }

# ── 1. Both clones exist, and only the wide one carries features ────
n_base=$(grep -cE "^define .*@($MARKED)[a-z0-9_]*\.base\(" "$WORK/on.ll")
n_wide=$(grep -cE "^define .*@($MARKED)[a-z0-9_]*\.x86v3\(" "$WORK/on.ll")
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
if grep -qE "^define i64 @__sum[a-z0-9_]*\(i8\* %p, i64 %n\) \{" "$WORK/on.ll"; then
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
n_off_fn=$(grep -cE "^define .*@($MARKED)[a-z0-9_]*\(" "$WORK/off.ll")
if [ "$n_off_fn" -ge 5 ]; then
    ok "--no-cpu-dispatch still defines the functions" "$n_off_fn"
else
    bad "--no-cpu-dispatch still defines the functions" "only $n_off_fn"
fi

# ── 4. --g suppresses cloning (a DISubprogram binds to one function) ─
"$NURLC" --g "$SRC" > "$WORK/g.ll" 2>/dev/null
n_g=$(grep -cE "^define .*(\.base|\.x86v3)\(" "$WORK/g.ll")
if [ "$n_g" -eq 0 ]; then
    ok "--g suppresses cloning" "0 clones"
else
    bad "--g suppresses cloning" "$n_g clones — !dbg would be attached twice"
fi

# ── 5. A marked module is not partitioned ───────────────────────────
rm -f "$WORK"/sp.*.ll
"$NURLC" --split=8 --split-out="$WORK/sp" "$SRC" > /dev/null 2>&1
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

echo ""
if [ "$fails" -eq 0 ]; then
    echo "simd_dispatch_ir: all assertions passed"
    exit 0
fi
echo "simd_dispatch_ir: $fails assertion(s) FAILED"
exit 1
