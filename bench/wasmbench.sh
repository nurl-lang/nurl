#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  bench/wasmbench.sh — the wasm benchmark runner.
#
#  The sibling of bench/bench.sh, same corpus and same protocol, one axis
#  rotated: instead of asking "how fast is NURL against four other
#  languages", it asks "what does *targeting wasm* cost, and what does
#  running that wasm on NURL's own runtime cost".
#
#  Every benchmark in bench/manifest.tsv is implemented in NURL, C and
#  Rust. Each of those three is compiled twice — native and wasm32-wasi —
#  and every wasm module is then run on two runtimes:
#
#    reference wasmtime   The external Bytecode Alliance runtime (Cranelift
#                         JIT), the industry baseline. The wasm-vs-native gap
#                         it shows is the cost of the *target*, with the
#                         compiler quality controlled for.
#    packages/nwasm       `nwasm`, a WebAssembly runtime written in pure
#                         NURL. Same modules, same outputs; the gap to the
#                         column on its left is the cost of *this runtime*.
#
#  Ten timed cells per row — 3 languages x {native, JIT, interpreter}, plus
#  the NURL module relinked with --no-gc-sections — all gated on printing the
#  same line as the native NURL binary. A speed number for a program
#  computing something else is worthless.
#
#  Artefacts:
#    bench/results/wasm-latest.json   machine-readable
#    bench/WASMRESULTS.md             the same run rendered for humans
#
#  Usage:
#      ./bench/wasmbench.sh                    # full suite, write both files
#      ./bench/wasmbench.sh --quick            # 1 rep/cell, for a smoke test
#      ./bench/wasmbench.sh --bench lcg --bench sieve
#      ./bench/wasmbench.sh --nwasm-all-langs   # + C/Rust on the interpreter
#      ./bench/wasmbench.sh --stdout           # print the report, touch nothing
#
#  Everything but the interpreter costs about what bench.sh does. The
#  interpreter is ~500x slower than native, so its column alone is ~15
#  minutes for NURL — that is the measurement, not a defect of the harness.
#  --nwasm-all-langs adds the C and Rust modules to it (the cross-frontend
#  control) and triples that, so it is opt-in rather than the default.
#
#  Requires nurlc (./build.sh), clang, rustc + the wasm32-wasip1 target,
#  zig (the toolchain's bundled one is fine) and the external reference
#  wasmtime.
#  A missing toolchain is a hard error: a table with a hole in it is worse
#  than no table, because the hole is invisible once the numbers are copied
#  out. `wasmbuilder` and `nwasm` are compiled from packages/ by this script,
#  so they always match the repo they are measuring.
# ============================================================
set -u

# $EPOCHREALTIME's decimal separator and awk's %f output both follow the
# locale; under e.g. fi_FI a comma where time_ms expects a dot turns
# compile times negative. Pin the whole run to C. (Same line bench.sh
# carries — CI runs under C.UTF-8 and never saw it, a workstation does.)
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_wasmbuild"
MANIFEST="$BENCH/manifest.tsv"

# ── settings ─────────────────────────────────────────────────────
MAX_REPS=5            # timed runs per cell, at most
BUDGET_MS=8000        # per-cell time budget; a slow cell gets fewer reps
TIMEOUT_S=900         # per-run wall-clock cap (the interpreter needs room)
COMPILE_REPS=3        # timed compiles per compiled language
OPT="-O2"
WASM_TARGET_C="wasm32-wasi"       # zig cc's spelling
WASM_TARGET_RS="wasm32-wasip1"    # rustc's spelling
JSON_OUT="$BENCH/results/wasm-latest.json"
MD_OUT="$BENCH/WASMRESULTS.md"
WRITE=1
NWASM_ALL_LANGS=0        # also run C/Rust on the interpreter (--nwasm-all-langs)
SELECTED=()

usage() { sed -n '4,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while (( $# > 0 )); do
    case "$1" in
        --bench)         SELECTED+=("$2"); shift 2 ;;
        --reps)          MAX_REPS="$2"; shift 2 ;;
        --budget-ms)     BUDGET_MS="$2"; shift 2 ;;
        --timeout)       TIMEOUT_S="$2"; shift 2 ;;
        --compile-reps)  COMPILE_REPS="$2"; shift 2 ;;
        --json)          JSON_OUT="$2"; shift 2 ;;
        --md)            MD_OUT="$2"; shift 2 ;;
        --stdout)        WRITE=0; shift ;;
        --nwasm-all-langs)  NWASM_ALL_LANGS=1; shift ;;
        --quick)         MAX_REPS=1; BUDGET_MS=1; COMPILE_REPS=1; shift ;;
        -h|--help)       usage 0 ;;
        *)               echo "wasmbench.sh: unknown argument '$1'" >&2; usage 2 ;;
    esac
done

mkdir -p "$BUILD"

# ── toolchain detection ──────────────────────────────────────────
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
NURL_HOME_DIR="${NURL_HOME:-$HOME/.nurl}"

missing=()
[[ -x "$NURLC" && -f "$RUNTIME" ]] || missing+=("nurlc (run ./build.sh)")
command -v clang >/dev/null || missing+=("clang")
command -v rustc >/dev/null || missing+=("rustc")

# zig carries its own wasi-libc and wasm-ld — that is what makes a wasi-sdk
# unnecessary, for the C column here and inside wasmbuilder alike. Same
# discovery order the wasmbuilder package uses, so both find the same zig.
ZIG="${NURL_ZIG:-}"
if [[ -z "$ZIG" ]]; then
    if   [[ -x "$NURL_HOME_DIR/zig/zig" ]]; then ZIG="$NURL_HOME_DIR/zig/zig"
    elif command -v zig >/dev/null;        then ZIG="$(command -v zig)"
    fi
fi
[[ -n "$ZIG" ]] || missing+=("zig (install the NURL toolchain, or set \$NURL_ZIG)")

# The reference runtime. Not vendored anywhere in this repo on purpose: its
# whole job here is to be the outside opinion.
WASMTIME="${WASMTIME:-}"
if [[ -z "$WASMTIME" ]]; then
    if   command -v wasmtime >/dev/null;            then WASMTIME="$(command -v wasmtime)"
    elif [[ -x "$HOME/.wasmtime/bin/wasmtime" ]];   then WASMTIME="$HOME/.wasmtime/bin/wasmtime"
    fi
fi
[[ -n "$WASMTIME" ]] || missing+=("wasmtime (curl https://wasmtime.dev/install.sh -sSf | bash)")

# rustc ships wasm32-wasip1 as a rustup component, not by default.
if command -v rustc >/dev/null; then
    rustc --print target-libdir --target "$WASM_TARGET_RS" >/dev/null 2>&1 \
        || missing+=("rust std for $WASM_TARGET_RS (rustup target add $WASM_TARGET_RS)")
fi

if (( ${#missing[@]} > 0 )); then
    printf 'wasmbench.sh: missing toolchain: %s\n' "${missing[*]}" >&2
    exit 1
fi

# Optional FFI libs the NURL runtime may have been built against — the same
# detection bench.sh does, so the native link line here matches a normal
# `nurl.sh` build byte for byte.
EXTRA_LIBS=""
for pair in "runtime.curl:libcurl" "runtime.openssl:openssl" "runtime.sqlite3:sqlite3" \
            "runtime.pq:libpq" "runtime.z:zlib" "runtime.zstd:libzstd"; do
    marker="${pair%%:*}"; pc="${pair##*:}"
    [[ -f "$ROOT/stdlib/$marker" ]] && EXTRA_LIBS="$EXTRA_LIBS $(pkg-config --libs "$pc" 2>/dev/null)"
done

# ── build the two packages under test ────────────────────────────
# wasmbuilder compiles the wasm; nwasm runs it. Both are NURL programs living
# in packages/, and both are rebuilt from source here rather than taken from
# an installed toolchain — a benchmark of this repo has to measure this
# repo's compiler, runtime and packages, not whatever happens to be in
# $NURL_HOME.
WASMBUILDER="$BUILD/wasmbuilder"
NWASM="$BUILD/nwasm"

#
# NURL_SPLIT=0: `nurl.sh` defaults to lowering a large program as one module
# per core so the clang step parallelises, and ThinLTO cannot import every
# callee back across a part boundary — docs/BUILDING.md puts the cost at
# 3.4 % of the program's own speed and says to turn it off for a release
# build. `nwasm` is not an incidental tool here, it is the subject of section 3,
# and the reference runtime it is measured against is a release build; a
# split `nwasm` measured 5.0 % slower over this corpus. Build time is not timed,
# so the trade has nothing to buy here.
echo "  building packages/wasmbuilder and packages/nwasm …" >&2
for pkg in "wasmbuilder:$WASMBUILDER" "nwasm:$NWASM"; do
    name="${pkg%%:*}"; out="${pkg##*:}"
    if ! (cd "$ROOT" && NURL_SPLIT=0 ./nurl.sh "packages/$name/src/main.nu" "$out") >"$out.buildlog" 2>&1; then
        echo "wasmbench.sh: failed to build packages/$name — see $out.buildlog" >&2
        exit 1
    fi
done

# wasmbuilder resolves nurlc and the stdlib C sources from the environment;
# point both at this repo so the wasm modules and the native binaries come
# out of the same compiler.
export NURLC
export NURL_STDLIB="$ROOT"

# First use compiles stdlib/runtime.c to runtime.wasm.o and caches it by
# content hash. Do that now, outside the timed region, or the first
# benchmark's compile cell would carry it.
"$WASMBUILDER" --doctor >/dev/null 2>&1

NURL_VERSION="$("$NURLC" --version 2>/dev/null | head -1)"
[[ -n "$NURL_VERSION" ]] || NURL_VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null)"
CLANG_VERSION="$(clang --version | head -1)"
RUSTC_VERSION="$(rustc --version)"
ZIG_VERSION="zig $("$ZIG" version 2>/dev/null)"
WASMTIME_VERSION="$("$WASMTIME" --version 2>/dev/null | head -1)"
WASMBUILDER_VERSION="$("$WASMBUILDER" --version 2>/dev/null | head -1)"
NWASM_VERSION="$("$NWASM" --version 2>/dev/null | head -1)"

HOST_KERNEL="$(uname -srm)"
HOST_CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')"
[[ -n "$HOST_CPU" ]] || HOST_CPU="$(uname -p)"
HOST_CORES="$(nproc 2>/dev/null || echo 0)"
HOST_MEM_KB="$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
[[ -n "$HOST_MEM_KB" ]] || HOST_MEM_KB=0
HOST_LABEL="${BENCH_HOST_LABEL:-$(uname -s) $(uname -m)}"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
RUN_URL="${BENCH_RUN_URL:-}"

# ── timing helpers ───────────────────────────────────────────────
# Identical to bench.sh's, deliberately: the two reports have to be
# comparable cell for cell. One wall-clock reading in milliseconds from
# bash 5's $EPOCHREALTIME rather than forking `date` twice, which would add
# ~3 ms to every reading — larger than several of the native cells.
time_ms() {
    local t0 t1 ec
    t0=$EPOCHREALTIME
    if [[ -n "${TIME_STDOUT:-}" ]]; then
        timeout --foreground "${TIMEOUT_S}s" "$@" >"$TIME_STDOUT" 2>/dev/null
    else
        timeout --foreground "${TIMEOUT_S}s" "$@" >/dev/null 2>&1
    fi
    ec=$?
    t1=$EPOCHREALTIME
    if [[ $ec -eq 124 ]]; then echo TIMEOUT; return; fi
    if [[ $ec -ne 0 ]];   then echo FAIL;    return; fi
    local sa=${t0%.*} ua=${t0#*.} sb=${t1%.*} ub=${t1#*.}
    awk -v us=$(( (sb * 1000000 + 10#$ub) - (sa * 1000000 + 10#$ua) )) \
        'BEGIN { printf "%.3f", us / 1000 }'
}

median() {
    local a
    for a in "$@"; do
        [[ "$a" == FAIL    ]] && { echo FAIL; return; }
        [[ "$a" == TIMEOUT ]] && { echo TIMEOUT; return; }
    done
    printf '%s\n' "$@" | sort -g | awk '{ v[NR]=$1 } END {
        if (NR % 2) printf "%.3f", v[(NR+1)/2]; else printf "%.3f", (v[NR/2] + v[NR/2+1]) / 2 }'
}

# Time a cell adaptively: one run first, then as many more as fit in
# BUDGET_MS, capped at MAX_REPS. A 6 ms native cell gets the full 5 runs for
# 30 ms; a 40-second interpreter cell gets one, because a second run buys
# noise reduction the reader cannot use and costs another 40 seconds.
# Echoes "<median_ms> <reps>".
time_cell() {
    local first rest reps runs=()
    first="$(time_ms "$@")"
    if [[ "$first" == FAIL || "$first" == TIMEOUT ]]; then echo "$first 1"; return; fi
    runs=("$first")
    reps="$(awk -v b="$BUDGET_MS" -v f="$first" -v m="$MAX_REPS" \
        'BEGIN { n = (f > 0) ? int(b / f) : m; if (n < 1) n = 1; if (n > m) n = m; print n }')"
    while (( ${#runs[@]} < reps )); do
        rest="$(time_ms "$@")"
        [[ "$rest" == FAIL || "$rest" == TIMEOUT ]] && { echo "$rest ${#runs[@]}"; return; }
        runs+=("$rest")
    done
    echo "$(median "${runs[@]}") ${#runs[@]}"
}

# ── compile helpers ──────────────────────────────────────────────
# nurlc resolves `$ "stdlib/..."` imports relative to its working directory,
# so every compile and every run happens from $ROOT. So does every wasm run:
# json_parse opens bench/data.json through a `--dir .` preopen.
compile_nurl_native() {    # <src.nu> <outbase> -> "<frontend_ms> <total_ms>" or FAIL
    local src="$1" ll="$2.ll" bin="$2.nurl.bin"
    local fe=() tot=() r f l
    for ((r = 0; r < COMPILE_REPS; r++)); do
        f="$(cd "$ROOT" && TIME_STDOUT="$ll" time_ms "$NURLC" "$src")"
        [[ "$f" == FAIL || "$f" == TIMEOUT ]] && { echo FAIL; return 1; }
        # shellcheck disable=SC2086
        l="$(cd "$ROOT" && time_ms clang $OPT -flto -Wl,--as-needed "$ll" "$RUNTIME" \
                 -lm -lpthread $EXTRA_LIBS -o "$bin")"
        [[ "$l" == FAIL || "$l" == TIMEOUT ]] && { echo FAIL; return 1; }
        fe+=("$f"); tot+=("$(awk -v a="$f" -v b="$l" 'BEGIN { printf "%.3f", a + b }')")
    done
    echo "$(median "${fe[@]}") $(median "${tot[@]}")"
}

# The whole wasmbuilder pipeline in one number: nurlc to LLVM IR, the IR
# rewriter retargeting it for wasm32-wasi, and zig cc linking the module
# against wasi-libc and the cached runtime.wasm.o. Comparable to the NURL
# native total in the same row.
compile_nurl_wasm() {      # <src.nu> <outbase> -> "<ms>" or FAIL
    local src="$1" out="$2.nu.wasm" res=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        t="$(cd "$ROOT" && time_ms "$WASMBUILDER" -q "$src" -o "$out")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        res+=("$t")
    done
    median "${res[@]}"
}

# The same pipeline with `--no-gc-sections` — what wasmbuilder's default
# USED to be, kept measured so the cost of ever needing the escape hatch
# (a call_indirect trap under table renumbering, not seen since the flip)
# stays a number instead of a memory. Built for every benchmark, gated on
# identical output like every other cell, reported beside the default in
# section 5.
compile_nurl_wasm_nogc() { # <src.nu> <outbase> -> "<ms>" or FAIL
    local src="$1" out="$2.nunogc.wasm" res=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        t="$(cd "$ROOT" && time_ms "$WASMBUILDER" -q --no-gc-sections "$src" -o "$out")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        res+=("$t")
    done
    median "${res[@]}"
}

compile_c_native() {       # <src.c> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.c.bin" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        # shellcheck disable=SC2086
        t="$(cd "$ROOT" && time_ms clang $OPT "$src" -lm -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

compile_c_wasm() {         # <src.c> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.c.wasm" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        # shellcheck disable=SC2086
        t="$(cd "$ROOT" && time_ms "$ZIG" cc "--target=$WASM_TARGET_C" $OPT "$src" -lm -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

compile_rust_native() {    # <src.rs> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.rs.bin" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        t="$(cd "$ROOT" && time_ms rustc -C opt-level=2 "$src" -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

compile_rust_wasm() {      # <src.rs> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.rs.wasm" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        t="$(cd "$ROOT" && time_ms rustc --target "$WASM_TARGET_RS" -C opt-level=2 "$src" -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

fsize() { [[ -f "$1" ]] && stat -c%s "$1" 2>/dev/null || echo 0; }

# ── roster ───────────────────────────────────────────────────────
names=(); blurbs=(); shapes=()
while IFS=$'\t' read -r name blurb shape; do
    [[ -z "${name:-}" || "$name" == \#* ]] && continue
    if (( ${#SELECTED[@]} > 0 )); then
        selected_hit=0
        for s in "${SELECTED[@]}"; do [[ "$s" == "$name" ]] && selected_hit=1; done
        (( selected_hit )) || continue
    fi
    names+=("$name"); blurbs+=("$blurb"); shapes+=("$shape")
done < "$MANIFEST"

if (( ${#names[@]} == 0 )); then
    echo "wasmbench.sh: no benchmarks selected" >&2
    exit 2
fi

# json_parse reads a generated fixture; make sure it exists before the gate
# runs, or every implementation fails identically and the row looks fine.
[[ -f "$BENCH/data.json" ]] || python3 "$BENCH/gen_data.py"

# ── run helpers ──────────────────────────────────────────────────
# Every wasm run gets `--dir .` — json_parse needs a preopen and the others
# pay the same cost, so the column stays internally comparable.
#
# `-C cache=n` turns off the reference runtime's on-disk compiled-module
# cache, which its CLI enables by default. Leaving it on makes a cell mean
# two different things depending on whether ~/.cache/wasmtime already holds
# that module: here the first rep would pay Cranelift and the rest would
# not, so the median silently reported a *warm* number while the floor row
# — measured once — could still be a cold one. Ratios computed across that
# boundary are nonsense (a benchmark came out ten times *faster* than its
# own empty program). With the cache off, every reference cell is
# decode + compile + run, exactly like every `nwasm` cell, both runtimes are
# measured doing the same work, and the floor row subtracts cleanly.
#
# These are argv prefixes rather than shell functions on purpose: time_ms
# runs its command under `timeout`, which execs a real binary and cannot see
# a function defined in this shell.
REF_RUN=("$WASMTIME" run -C cache=n --dir .)
NWASM_RUN=("$NWASM" run --dir .)

# ── process-start-up floor ───────────────────────────────────────
# What each cell costs for a program that does nothing. On the two wasm
# columns this is not a small number and not a constant one: the reference
# runtime JIT-compiles the whole module before `_start`, and the interpreter
# decodes it — and a NURL "empty" module still links the entire runtime, so
# its floor is the floor of a ~1 MB module. Subtract the floor to read the
# marginal cost of the benchmark itself.
floor_dir="$BUILD/floor"
mkdir -p "$floor_dir"
printf '@ main → i {\n    ^ 0\n}\n'      > "$floor_dir/floor.nu"
printf 'int main(void) { return 0; }\n'  > "$floor_dir/floor.c"
printf 'fn main() {}\n'                  > "$floor_dir/floor.rs"

echo "  measuring the floor …" >&2
read -r floor_cc_nurl_fe floor_cc_nurl <<<"$(compile_nurl_native "$floor_dir/floor.nu" "$floor_dir/floor")"
floor_cc_nurl_wasm="$(compile_nurl_wasm "$floor_dir/floor.nu" "$floor_dir/floor")"
floor_cc_nurl_wasm_nogc="$(compile_nurl_wasm_nogc "$floor_dir/floor.nu" "$floor_dir/floor")"
floor_cc_c="$(compile_c_native "$floor_dir/floor.c" "$floor_dir/floor")"
floor_cc_c_wasm="$(compile_c_wasm "$floor_dir/floor.c" "$floor_dir/floor")"
floor_cc_rust="$(compile_rust_native "$floor_dir/floor.rs" "$floor_dir/floor")"
floor_cc_rust_wasm="$(compile_rust_wasm "$floor_dir/floor.rs" "$floor_dir/floor")"

read -r floor_nurl _      <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.nurl.bin")"
read -r floor_c _         <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.c.bin")"
read -r floor_rust _      <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.rs.bin")"
read -r floor_nurl_ref _  <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$floor_dir/floor.nu.wasm")"
read -r floor_nurl_ref_nogc _ <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$floor_dir/floor.nunogc.wasm")"
read -r floor_c_ref _     <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$floor_dir/floor.c.wasm")"
read -r floor_rust_ref _  <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$floor_dir/floor.rs.wasm")"
read -r floor_nurl_nw _   <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$floor_dir/floor.nu.wasm")"
if (( NWASM_ALL_LANGS )); then
    read -r floor_c_nw _    <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$floor_dir/floor.c.wasm")"
    read -r floor_rust_nw _ <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$floor_dir/floor.rs.wasm")"
else
    floor_c_nw=SKIPPED; floor_rust_nw=SKIPPED
fi

# ── measure ──────────────────────────────────────────────────────
# Per-benchmark results as parallel arrays, in manifest order.
r_checksum=(); r_verified=(); r_detail=()
r_nurl=(); r_c=(); r_rust=()
r_nurl_ref=(); r_c_ref=(); r_rust_ref=()
r_nurl_nw=(); r_c_nw=(); r_rust_nw=()
r_nurl_reps=(); r_c_reps=(); r_rust_reps=()
r_nurl_ref_reps=(); r_c_ref_reps=(); r_rust_ref_reps=()
r_nurl_nw_reps=(); r_c_nw_reps=(); r_rust_nw_reps=()
r_cc_nurl_fe=(); r_cc_nurl=(); r_cc_nurl_wasm=()
r_cc_c=(); r_cc_c_wasm=(); r_cc_rust=(); r_cc_rust_wasm=()
r_sz_nurl=(); r_sz_nurl_wasm=(); r_sz_c=(); r_sz_c_wasm=(); r_sz_rust=(); r_sz_rust_wasm=()
# the --no-gc-sections variant of the NURL module (section 5)
r_cc_nurl_wasm_nogc=(); r_sz_nurl_wasm_nogc=(); r_nurl_ref_nogc=(); r_nurl_ref_nogc_reps=()

progress() { printf '\r\033[K  %-18s %s' "$1" "$2" >&2; }

for idx in "${!names[@]}"; do
    b="${names[$idx]}"

    progress "$b" "compiling native…"
    read -r cc_fe cc_nurl <<<"$(compile_nurl_native "$BENCH/$b.nu" "$BUILD/$b")"
    cc_c="$(compile_c_native "$BENCH/$b.c" "$BUILD/$b")"
    cc_rust="$(compile_rust_native "$BENCH/$b.rs" "$BUILD/$b")"
    progress "$b" "compiling wasm…"
    cc_nurl_wasm="$(compile_nurl_wasm "$BENCH/$b.nu" "$BUILD/$b")"
    cc_nurl_wasm_nogc="$(compile_nurl_wasm_nogc "$BENCH/$b.nu" "$BUILD/$b")"
    cc_c_wasm="$(compile_c_wasm "$BENCH/$b.c" "$BUILD/$b")"
    cc_rust_wasm="$(compile_rust_wasm "$BENCH/$b.rs" "$BUILD/$b")"
    r_cc_nurl_fe+=("${cc_fe:-FAIL}"); r_cc_nurl+=("${cc_nurl:-FAIL}")
    r_cc_nurl_wasm+=("$cc_nurl_wasm"); r_cc_nurl_wasm_nogc+=("$cc_nurl_wasm_nogc")
    r_cc_c+=("$cc_c"); r_cc_c_wasm+=("$cc_c_wasm")
    r_cc_rust+=("$cc_rust"); r_cc_rust_wasm+=("$cc_rust_wasm")

    r_sz_nurl+=("$(fsize "$BUILD/$b.nurl.bin")")
    r_sz_nurl_wasm+=("$(fsize "$BUILD/$b.nu.wasm")")
    r_sz_nurl_wasm_nogc+=("$(fsize "$BUILD/$b.nunogc.wasm")")
    r_sz_c+=("$(fsize "$BUILD/$b.c.bin")")
    r_sz_c_wasm+=("$(fsize "$BUILD/$b.c.wasm")")
    r_sz_rust+=("$(fsize "$BUILD/$b.rs.bin")")
    r_sz_rust_wasm+=("$(fsize "$BUILD/$b.rs.wasm")")

    # ── the gate ──
    # Ten cells, one expected line. The native NURL output is the reference
    # the other nine are compared against; the interpreter is included in
    # the gate, so a wrong answer from `nwasm` drops the row rather than being
    # reported as a fast cell.
    progress "$b" "verifying native + JIT…"
    out_nurl="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.nurl.bin" 2>/dev/null)"
    out_c="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.c.bin" 2>/dev/null)"
    out_rust="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.rs.bin" 2>/dev/null)"
    out_nurl_ref="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${REF_RUN[@]}" "$BUILD/$b.nu.wasm" 2>/dev/null)"
    out_c_ref="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${REF_RUN[@]}" "$BUILD/$b.c.wasm" 2>/dev/null)"
    out_rust_ref="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${REF_RUN[@]}" "$BUILD/$b.rs.wasm" 2>/dev/null)"
    out_nurl_ref_nogc="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${REF_RUN[@]}" "$BUILD/$b.nunogc.wasm" 2>/dev/null)"

    progress "$b" "verifying interpreter…"
    out_nurl_nw="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${NWASM_RUN[@]}" "$BUILD/$b.nu.wasm" 2>/dev/null)"
    if (( NWASM_ALL_LANGS )); then
        out_c_nw="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${NWASM_RUN[@]}" "$BUILD/$b.c.wasm" 2>/dev/null)"
        out_rust_nw="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "${NWASM_RUN[@]}" "$BUILD/$b.rs.wasm" 2>/dev/null)"
    else
        out_c_nw="$out_nurl"; out_rust_nw="$out_nurl"   # not run: excluded from the gate
    fi

    verified=true; detail=""
    for pair in "NURL:$out_nurl" "C:$out_c" "Rust:$out_rust" \
                "NURL/wasm:$out_nurl_ref" "C/wasm:$out_c_ref" "Rust/wasm:$out_rust_ref" \
                "NURL/wasm+nogc:$out_nurl_ref_nogc" \
                "NURL/nwasm:$out_nurl_nw" "C/nwasm:$out_c_nw" "Rust/nwasm:$out_rust_nw"; do
        lang="${pair%%:*}"; got="${pair#*:}"
        # An empty line fails the gate even when every cell agrees on it:
        # nine programs that all printed nothing agree about nothing.
        if [[ "$got" != "$out_nurl" || -z "$got" ]]; then
            verified=false
            detail="$detail${detail:+, }$lang=${got:-<empty>}"
        fi
    done
    [[ -n "$detail" ]] || detail="all ten cells printed ${out_nurl:-<empty>}"
    r_checksum+=("$out_nurl"); r_verified+=("$verified"); r_detail+=("$detail")

    if [[ "$verified" != true ]]; then
        printf '\r\033[K  %-18s MISMATCH — %s\n' "$b" "$detail" >&2
        r_nurl+=(SKIPPED); r_c+=(SKIPPED); r_rust+=(SKIPPED)
        r_nurl_ref+=(SKIPPED); r_c_ref+=(SKIPPED); r_rust_ref+=(SKIPPED)
        r_nurl_nw+=(SKIPPED); r_c_nw+=(SKIPPED); r_rust_nw+=(SKIPPED)
        r_nurl_ref_nogc+=(SKIPPED); r_nurl_ref_nogc_reps+=(0)
        r_nurl_reps+=(0); r_c_reps+=(0); r_rust_reps+=(0)
        r_nurl_ref_reps+=(0); r_c_ref_reps+=(0); r_rust_ref_reps+=(0)
        r_nurl_nw_reps+=(0); r_c_nw_reps+=(0); r_rust_nw_reps+=(0)
        continue
    fi

    progress "$b" "timing NURL native…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.nurl.bin")"
    r_nurl+=("$ms"); r_nurl_reps+=("$reps")
    progress "$b" "timing C native…";    read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.c.bin")"
    r_c+=("$ms"); r_c_reps+=("$reps")
    progress "$b" "timing Rust native…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.rs.bin")"
    r_rust+=("$ms"); r_rust_reps+=("$reps")

    progress "$b" "timing NURL wasm (JIT)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$BUILD/$b.nu.wasm")"
    r_nurl_ref+=("$ms"); r_nurl_ref_reps+=("$reps")
    progress "$b" "timing C wasm (JIT)…";    read -r ms reps <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$BUILD/$b.c.wasm")"
    r_c_ref+=("$ms"); r_c_ref_reps+=("$reps")
    progress "$b" "timing Rust wasm (JIT)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$BUILD/$b.rs.wasm")"
    r_rust_ref+=("$ms"); r_rust_ref_reps+=("$reps")
    progress "$b" "timing NURL wasm+nogc (JIT)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${REF_RUN[@]}" "$BUILD/$b.nunogc.wasm")"
    r_nurl_ref_nogc+=("$ms"); r_nurl_ref_nogc_reps+=("$reps")

    progress "$b" "timing NURL wasm (nwasm)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$BUILD/$b.nu.wasm")"
    r_nurl_nw+=("$ms"); r_nurl_nw_reps+=("$reps")
    if (( NWASM_ALL_LANGS )); then
        progress "$b" "timing C wasm (nwasm)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$BUILD/$b.c.wasm")"
        r_c_nw+=("$ms"); r_c_nw_reps+=("$reps")
        progress "$b" "timing Rust wasm (nwasm)…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell "${NWASM_RUN[@]}" "$BUILD/$b.rs.wasm")"
        r_rust_nw+=("$ms"); r_rust_nw_reps+=("$reps")
    else
        r_c_nw+=(SKIPPED); r_c_nw_reps+=(0)
        r_rust_nw+=(SKIPPED); r_rust_nw_reps+=(0)
    fi

    printf '\r\033[K  %-18s native %8s  jit %8s  nwasm %10s   (nurl)\n' \
        "$b" "${r_nurl[$idx]}" "${r_nurl_ref[$idx]}" "${r_nurl_nw[$idx]}" >&2
done
printf '\r\033[K' >&2

# ── emit ─────────────────────────────────────────────────────────
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
jnum() { [[ "$1" =~ ^[0-9.]+$ ]] && printf '%s' "$1" || printf 'null'; }

# "how many times slower than the cell to compare against", or an em dash
# when either end is missing.
ratio() { awk -v a="$1" -v b="$2" \
    'BEGIN { if (a ~ /^[0-9.]+$/ && b ~ /^[0-9.]+$/ && b + 0 > 0) printf "%.1f", a / b; else printf "—" }'; }
# The same, with the floor of each column subtracted first: the marginal
# cost of the benchmark, with start-up (and, on wasm, module compilation)
# taken out of both ends.
#
# Refuses to print when a floor is more than half of the cell it is being
# taken out of. Past that point the answer is a difference of two similar
# numbers and inherits both their errors — the first version of this table
# reported Rust `prefix_scan` at 0.5x, i.e. wasm running the benchmark
# twice as fast as the machine did, purely because 17 ms of floor came out
# of a 29 ms cell. A missing number is honest; that one was not.
ratio_net() { awk -v a="$1" -v af="$2" -v b="$3" -v bf="$4" 'BEGIN {
    if (a !~ /^[0-9.]+$/ || b !~ /^[0-9.]+$/ || af !~ /^[0-9.]+$/ || bf !~ /^[0-9.]+$/) { printf "—"; exit }
    an = a - af; bn = b - bf
    if (an <= 0 || bn <= 0) { printf "—"; exit }
    if (an < a / 2 || bn < b / 2) { printf "—"; exit }
    printf "%.1f", an / bn }'; }

emit_json() {
    printf '{\n'
    printf '  "schema": 1,\n'
    printf '  "kind": "wasm",\n'
    printf '  "generated_utc": "%s",\n' "$(jstr "$NOW")"
    printf '  "commit": "%s",\n' "$(jstr "$COMMIT")"
    printf '  "run_url": "%s",\n' "$(jstr "$RUN_URL")"
    printf '  "host": {\n'
    printf '    "label": "%s",\n'  "$(jstr "$HOST_LABEL")"
    printf '    "kernel": "%s",\n' "$(jstr "$HOST_KERNEL")"
    printf '    "cpu": "%s",\n'    "$(jstr "$HOST_CPU")"
    printf '    "cores": %s,\n'    "$(jnum "$HOST_CORES")"
    printf '    "mem_kb": %s\n'    "$(jnum "$HOST_MEM_KB")"
    printf '  },\n'
    printf '  "toolchains": {\n'
    printf '    "nurl": "%s",\n'        "$(jstr "$NURL_VERSION")"
    printf '    "clang": "%s",\n'       "$(jstr "$CLANG_VERSION")"
    printf '    "rustc": "%s",\n'       "$(jstr "$RUSTC_VERSION")"
    printf '    "zig": "%s",\n'         "$(jstr "$ZIG_VERSION")"
    printf '    "wasmbuilder": "%s",\n' "$(jstr "$WASMBUILDER_VERSION")"
    printf '    "wasm_runtime_ref": "%s",\n' "$(jstr "$WASMTIME_VERSION")"
    printf '    "wasm_runtime_nurl": "%s"\n' "$(jstr "$NWASM_VERSION")"
    printf '  },\n'
    printf '  "settings": {\n'
    printf '    "opt": "%s",\n' "$(jstr "$OPT")"
    printf '    "wasm_target_c": "%s",\n' "$(jstr "$WASM_TARGET_C")"
    printf '    "wasm_target_rust": "%s",\n' "$(jstr "$WASM_TARGET_RS")"
    printf '    "max_reps": %s,\n' "$MAX_REPS"
    printf '    "budget_ms": %s,\n' "$BUDGET_MS"
    printf '    "timeout_s": %s,\n' "$TIMEOUT_S"
    printf '    "compile_reps": %s,\n' "$COMPILE_REPS"
    printf '    "interpreter_all_languages": %s\n' "$( (( NWASM_ALL_LANGS )) && echo true || echo false )"
    printf '  },\n'
    printf '  "floor_ms": {\n'
    printf '    "native": { "nurl": %s, "c": %s, "rust": %s },\n' \
        "$(jnum "$floor_nurl")" "$(jnum "$floor_c")" "$(jnum "$floor_rust")"
    printf '    "wasm_ref": { "nurl": %s, "c": %s, "rust": %s, "nurl_no_gc_sections": %s },\n' \
        "$(jnum "$floor_nurl_ref")" "$(jnum "$floor_c_ref")" "$(jnum "$floor_rust_ref")" \
        "$(jnum "$floor_nurl_ref_nogc")"
    printf '    "wasm_nwasm": { "nurl": %s, "c": %s, "rust": %s }\n' \
        "$(jnum "$floor_nurl_nw")" "$(jnum "$floor_c_nw")" "$(jnum "$floor_rust_nw")"
    printf '  },\n'
    printf '  "floor_compile_ms": { "nurl_frontend": %s, "nurl_native": %s, "nurl_wasm": %s, "nurl_wasm_no_gc_sections": %s, "c_native": %s, "c_wasm": %s, "rust_native": %s, "rust_wasm": %s },\n' \
        "$(jnum "$floor_cc_nurl_fe")" "$(jnum "$floor_cc_nurl")" "$(jnum "$floor_cc_nurl_wasm")" \
        "$(jnum "$floor_cc_nurl_wasm_nogc")" \
        "$(jnum "$floor_cc_c")" "$(jnum "$floor_cc_c_wasm")" \
        "$(jnum "$floor_cc_rust")" "$(jnum "$floor_cc_rust_wasm")"
    printf '  "benchmarks": [\n'
    local i last=$(( ${#names[@]} - 1 ))
    for i in "${!names[@]}"; do
        printf '    {\n'
        printf '      "name": "%s",\n'     "$(jstr "${names[$i]}")"
        printf '      "blurb": "%s",\n'    "$(jstr "${blurbs[$i]}")"
        printf '      "measures": "%s",\n' "$(jstr "${shapes[$i]}")"
        printf '      "checksum": "%s",\n' "$(jstr "${r_checksum[$i]}")"
        printf '      "verified": %s,\n'   "${r_verified[$i]}"
        printf '      "run_ms": {\n'
        printf '        "native":   { "nurl": %s, "c": %s, "rust": %s },\n' \
            "$(jnum "${r_nurl[$i]}")" "$(jnum "${r_c[$i]}")" "$(jnum "${r_rust[$i]}")"
        printf '        "wasm_ref": { "nurl": %s, "c": %s, "rust": %s, "nurl_no_gc_sections": %s },\n' \
            "$(jnum "${r_nurl_ref[$i]}")" "$(jnum "${r_c_ref[$i]}")" "$(jnum "${r_rust_ref[$i]}")" \
            "$(jnum "${r_nurl_ref_nogc[$i]}")"
        printf '        "wasm_nwasm":  { "nurl": %s, "c": %s, "rust": %s }\n' \
            "$(jnum "${r_nurl_nw[$i]}")" "$(jnum "${r_c_nw[$i]}")" "$(jnum "${r_rust_nw[$i]}")"
        printf '      },\n'
        printf '      "reps": {\n'
        printf '        "native":   { "nurl": %s, "c": %s, "rust": %s },\n' \
            "${r_nurl_reps[$i]}" "${r_c_reps[$i]}" "${r_rust_reps[$i]}"
        printf '        "wasm_ref": { "nurl": %s, "c": %s, "rust": %s, "nurl_no_gc_sections": %s },\n' \
            "${r_nurl_ref_reps[$i]}" "${r_c_ref_reps[$i]}" "${r_rust_ref_reps[$i]}" \
            "${r_nurl_ref_nogc_reps[$i]}"
        printf '        "wasm_nwasm":  { "nurl": %s, "c": %s, "rust": %s }\n' \
            "${r_nurl_nw_reps[$i]}" "${r_c_nw_reps[$i]}" "${r_rust_nw_reps[$i]}"
        printf '      },\n'
        printf '      "compile_ms": { "nurl_frontend": %s, "nurl_native": %s, "nurl_wasm": %s, "nurl_wasm_no_gc_sections": %s, "c_native": %s, "c_wasm": %s, "rust_native": %s, "rust_wasm": %s },\n' \
            "$(jnum "${r_cc_nurl_fe[$i]}")" "$(jnum "${r_cc_nurl[$i]}")" "$(jnum "${r_cc_nurl_wasm[$i]}")" \
            "$(jnum "${r_cc_nurl_wasm_nogc[$i]}")" \
            "$(jnum "${r_cc_c[$i]}")" "$(jnum "${r_cc_c_wasm[$i]}")" \
            "$(jnum "${r_cc_rust[$i]}")" "$(jnum "${r_cc_rust_wasm[$i]}")"
        printf '      "bytes": { "nurl_native": %s, "nurl_wasm": %s, "nurl_wasm_no_gc_sections": %s, "c_native": %s, "c_wasm": %s, "rust_native": %s, "rust_wasm": %s }\n' \
            "${r_sz_nurl[$i]}" "${r_sz_nurl_wasm[$i]}" "${r_sz_nurl_wasm_nogc[$i]}" \
            "${r_sz_c[$i]}" "${r_sz_c_wasm[$i]}" \
            "${r_sz_rust[$i]}" "${r_sz_rust_wasm[$i]}"
        printf '    }%s\n' "$( (( i < last )) && echo ',' )"
    done
    printf '  ]\n'
    printf '}\n'
}

kib() { awk -v b="$1" 'BEGIN { if (b + 0 > 0) printf "%.0f", b / 1024; else printf "—" }'; }

# Signed percentage change from <before> to <after>, e.g. "−23 %".
pct() { awk -v a="$1" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9.]+$/ || b !~ /^[0-9.]+$/ || a + 0 <= 0) { printf "—"; exit }
    d = (b - a) * 100 / a
    printf "%s%.0f %%", (d > 0 ? "+" : (d < 0 ? "−" : "")), (d < 0 ? -d : d) }'; }

emit_md() {
    printf '# WebAssembly benchmark results — NURL native vs NURL wasm\n\n'
    printf 'Generated `%s` by `bench/wasmbench.sh`. **Do not edit by hand** —\n' "$NOW"
    printf 'the next run overwrites it. The machine-readable form of this same run\n'
    printf 'is [`results/wasm-latest.json`](results/wasm-latest.json).\n\n'
    printf 'This is the sibling of [`RESULTS.md`](RESULTS.md): same corpus, same\n'
    printf 'protocol, one axis rotated. `RESULTS.md` asks how fast NURL is against\n'
    printf 'four other languages; this file asks what **targeting wasm** costs, and\n'
    printf "what running that wasm on **NURL's own runtime** costs. Every benchmark\n"
    printf 'is compiled to a native binary *and* a `wasm32-wasi` module in three\n'
    printf 'languages, and each module is run on two runtimes — ten timed cells per\n'
    printf 'row, all gated on printing the same line (section 7).\n\n'

    printf '## Environment\n\n| Item | Value |\n|---|---|\n'
    printf '| Host | `%s` |\n' "$HOST_LABEL"
    printf '| Kernel | `%s` |\n' "$HOST_KERNEL"
    printf '| CPU | %s (%s logical cores) |\n' "$HOST_CPU" "$HOST_CORES"
    printf '| Memory | %s KiB |\n' "$HOST_MEM_KB"
    printf '| Commit | `%s` |\n' "$COMMIT"
    [[ -n "$RUN_URL" ]] && printf '| CI run | %s |\n' "$RUN_URL"
    printf '| NURL | `%s` |\n' "$NURL_VERSION"
    printf '| C | %s |\n' "$CLANG_VERSION"
    printf '| Rust | %s |\n' "$RUSTC_VERSION"
    printf '\n'
    printf '| Component | Value |\n|---|---|\n'
    printf '| NURL → wasm | `packages/wasmbuilder` (%s), built from this repo |\n' "$WASMBUILDER_VERSION"
    printf '| C → wasm | `%s cc --target=%s` |\n' "$ZIG_VERSION" "$WASM_TARGET_C"
    printf '| Rust → wasm | `rustc --target %s` |\n' "$WASM_TARGET_RS"
    printf '| wasm runtime (reference) | `%s` — Cranelift JIT |\n' "$WASMTIME_VERSION"
    printf '| wasm runtime (NURL) | `packages/nwasm` (%s) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |\n' "$NWASM_VERSION"
    printf '\n'
    printf '| Setting | Value |\n|---|---|\n'
    printf '| Optimisation | NURL/C `%s`, Rust `-C opt-level=2`, both targets |\n' "$OPT"
    printf '| Timed runs per cell | up to %s, adaptive: as many as fit in %s ms |\n' "$MAX_REPS" "$BUDGET_MS"
    printf '| Timed compiles per cell | %s (median) |\n' "$COMPILE_REPS"
    printf '| Per-run timeout | %s s |\n' "$TIMEOUT_S"
    printf '| C/Rust on the NURL interpreter | %s |\n' "$( (( NWASM_ALL_LANGS )) && echo 'yes' || echo 'no (add --nwasm-all-langs)' )"
    printf '| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |\n'
    printf '| `nwasm` build | `NURL_SPLIT=0` — `nurl.sh` otherwise lowers a large program as one module per core, and ThinLTO cannot import every callee back across a part boundary. `nwasm` is the subject of section 3, and the reference runtime it is measured against is a release build; a split `nwasm` measured 5.0%% slower over this corpus. |\n'
    printf '\n'

    printf '## 1. What wasm costs — native vs the same module on a JIT\n\n'
    printf 'Whole-process wall clock in milliseconds, start-up included. The `x`\n'
    printf 'columns are wasm ÷ native for that language: how much slower the *same\n'
    printf 'source* got by being compiled to wasm and run under a JIT instead of\n'
    printf 'straight to the machine. Because all three languages appear, the column\n'
    printf 'answers a question a NURL-only table could not: whether a gap belongs to\n'
    printf "NURL's wasm pipeline or to wasm itself.\n\n"
    printf '| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |\n'
    printf '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ |\n' \
        "$floor_nurl" "$floor_nurl_ref" "$(ratio "$floor_nurl_ref" "$floor_nurl")" \
        "$floor_c" "$floor_c_ref" "$(ratio "$floor_c_ref" "$floor_c")" \
        "$floor_rust" "$floor_rust_ref" "$(ratio "$floor_rust_ref" "$floor_rust")"
    local i
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "${r_nurl[$i]}" "${r_nurl_ref[$i]}" "$(ratio "${r_nurl_ref[$i]}" "${r_nurl[$i]}")" \
            "${r_c[$i]}" "${r_c_ref[$i]}" "$(ratio "${r_c_ref[$i]}" "${r_c[$i]}")" \
            "${r_rust[$i]}" "${r_rust_ref[$i]}" "$(ratio "${r_rust_ref[$i]}" "${r_rust[$i]}")"
    done
    printf '\n'
    printf 'The floor row matters more here than in `RESULTS.md`. A wasm cell pays\n'
    printf 'for the runtime compiling the whole module before `_start` runs, and a\n'
    printf 'NURL module links the entire NURL runtime whatever the program does — so\n'
    printf 'even the empty program is a ~1 MB module to JIT. Section 2 subtracts that\n'
    printf 'floor from both ends to show the steady-state ratio.\n\n'

    printf '## 2. The same ratios, with start-up subtracted\n\n'
    printf 'Cell minus the floor of its own column, wasm ÷ native. This is the\n'
    printf 'number to quote for a long-running program, where module compilation is\n'
    printf 'amortised to nothing; section 1 is the number to quote for a short one,\n'
    printf 'where it is most of the run.\n\n'
    printf 'A `—` means the subtraction has no signal left in it: the floor is more\n'
    printf 'than half of that cell, so the remainder is a difference of two similar\n'
    printf 'numbers carrying both their errors. The `no gc` column is the\n'
    printf 'pre-0.1.4 default relinked with `--no-gc-sections` (section 5); its\n'
    printf 'floor is big enough that most of its rows land there, which is one of\n'
    printf 'the reasons it is no longer the default.\n\n'
    printf '| Benchmark | NURL x | NURL no-gc x | C x | Rust x |\n|---|---:|---:|---:|---:|\n'
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s |\n' "${names[$i]}" \
            "$(ratio_net "${r_nurl_ref[$i]}" "$floor_nurl_ref" "${r_nurl[$i]}" "$floor_nurl")" \
            "$(ratio_net "${r_nurl_ref_nogc[$i]}" "$floor_nurl_ref_nogc" "${r_nurl[$i]}" "$floor_nurl")" \
            "$(ratio_net "${r_c_ref[$i]}" "$floor_c_ref" "${r_c[$i]}" "$floor_c")" \
            "$(ratio_net "${r_rust_ref[$i]}" "$floor_rust_ref" "${r_rust[$i]}" "$floor_rust")"
    done
    printf '\n'

    printf '## 3. The pure-NURL runtime (`packages/nwasm`)\n\n'
    printf 'The identical modules from section 1, executed by a runtime written in\n'
    printf 'NURL instead of in Rust: a register-record interpreter with a template\n'
    printf 'JIT on top (on by default; `NURL_NWASM_JIT=0` keeps the pure interpreter,\n'
    printf 'and metered or shared-memory runs fall back to it on their own).\n'
    printf '`vs JIT` is the cost of the runtime; `vs native` is the end-to-end\n'
    printf 'cost of choosing this way to ship. The size of the gap is measured\n'
    printf 'rather than assumed, per benchmark, so it can be aimed at.\n\n'
    printf 'Read the floor row first, because it goes the other way: on a program\n'
    printf 'that does nothing this runtime *beats* the reference. Nothing surprising\n'
    printf 'is happening — the reference compiles the whole module before `_start`,\n'
    printf 'and `nwasm` only decodes it, compiling nothing but what runs. That\n'
    printf 'crossover is the honest answer to "which runtime should I use": it\n'
    printf 'depends entirely on how long the guest runs.\n\n'
    printf '| Benchmark | NURL on `nwasm` | vs JIT | vs native | C on `nwasm` | Rust on `nwasm` |\n'
    printf '|---|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ |\n' \
        "$floor_nurl_nw" "$(ratio "$floor_nurl_nw" "$floor_nurl_ref")" \
        "$(ratio "$floor_nurl_nw" "$floor_nurl")" "$floor_c_nw" "$floor_rust_nw"
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "${r_nurl_nw[$i]}" \
            "$(ratio "${r_nurl_nw[$i]}" "${r_nurl_ref[$i]}")" \
            "$(ratio "${r_nurl_nw[$i]}" "${r_nurl[$i]}")" \
            "${r_c_nw[$i]}" "${r_rust_nw[$i]}"
    done
    printf '\n'
    if (( NWASM_ALL_LANGS )); then
        printf 'The C and Rust columns are the control. They are modules this runtime\n'
        printf 'never saw during development, emitted by two other LLVM frontends; that\n'
        printf 'they run at all is a correctness result, and that they run at a similar\n'
        printf 'ratio says the interpreter has no NURL-shaped fast path.\n\n'
    else
        printf 'The C and Rust columns are `SKIPPED`: they are the cross-frontend\n'
        printf 'control — modules this runtime never saw during development, from two\n'
        printf 'other LLVM frontends — and running them costs about three times the\n'
        printf 'whole rest of the suite, so they are opt-in. `--nwasm-all-langs` fills\n'
        printf 'them in. Until it is run, this section says what the interpreter does\n'
        printf 'with NURL output and nothing about whether it is tuned for it.\n\n'
    fi

    printf '## 4. Artefact size (KiB)\n\n'
    printf 'A wasm module carries its own copy of everything it links — wasi-libc,\n'
    printf 'the language runtime — where a native binary borrows the system one.\n'
    printf 'These are the bytes that have to be shipped, and (for the two runtimes\n'
    printf 'above) parsed before the program starts.\n\n'
    printf '| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |\n'
    printf '|---|---:|---:|---:|---:|---:|---:|\n'
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "$(kib "${r_sz_nurl[$i]}")" "$(kib "${r_sz_nurl_wasm[$i]}")" \
            "$(kib "${r_sz_c[$i]}")" "$(kib "${r_sz_c_wasm[$i]}")" \
            "$(kib "${r_sz_rust[$i]}")" "$(kib "${r_sz_rust_wasm[$i]}")"
    done
    printf '\n'

    printf '## 5. Dead code — what `--no-gc-sections` would cost\n\n'
    printf 'Every NURL module above was linked with `-Wl,--gc-sections`, the\n'
    printf '`wasmbuilder` default since 0.1.4: the unreachable part of the NURL\n'
    printf 'runtime is dropped instead of shipped and JIT-translated for nothing.\n'
    printf 'The old default, `--no-gc-sections`, exists as an escape hatch for a\n'
    printf 'closure/table-renumbering hazard that no longer reproduces — a\n'
    printf '`--gc-sections` `nurlc.wasm` self-compiles byte-identically under both\n'
    printf 'runtimes. These rows are the same benchmarks relinked with the escape\n'
    printf 'hatch, held to the same output, so its price stays a number: what you\n'
    printf 'pay in bytes and module-load time if you ever have to reach for it.\n\n'
    printf '| Benchmark | Size | Size no-gc | Δ | JIT | JIT no-gc | Δ |\n'
    printf '|---|---:|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ |\n' \
        "$(kib "$(fsize "$floor_dir/floor.nu.wasm")")" "$(kib "$(fsize "$floor_dir/floor.nunogc.wasm")")" \
        "$(pct "$(fsize "$floor_dir/floor.nu.wasm")" "$(fsize "$floor_dir/floor.nunogc.wasm")")" \
        "$floor_nurl_ref" "$floor_nurl_ref_nogc" "$(pct "$floor_nurl_ref" "$floor_nurl_ref_nogc")"
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "$(kib "${r_sz_nurl_wasm[$i]}")" "$(kib "${r_sz_nurl_wasm_nogc[$i]}")" \
            "$(pct "${r_sz_nurl_wasm[$i]}" "${r_sz_nurl_wasm_nogc[$i]}")" \
            "${r_nurl_ref[$i]}" "${r_nurl_ref_nogc[$i]}" \
            "$(pct "${r_nurl_ref[$i]}" "${r_nurl_ref_nogc[$i]}")"
    done
    printf '\n'
    printf 'The cost is almost all fixed, so it is largest where the benchmark\n'
    printf 'itself is smallest — compare each row against the floor. It is reported\n'
    printf 'on the JIT and not on the interpreter because the interpreter is\n'
    printf 'execution-bound, not decode-bound: its floor row in section 3 is a few\n'
    printf 'tens of milliseconds against cells in the tens of *seconds*, so module\n'
    printf 'size cannot move it either way.\n\n'

    printf '## 6. Compile time (median, ms)\n\n'
    printf 'The NURL wasm build is `wasmbuilder`: `nurlc` emits host LLVM IR, the IR\n'
    printf 'rewriter retargets it for `wasm32-wasi`, and the toolchain-bundled\n'
    printf '`zig cc` links it against wasi-libc and a cached `runtime.wasm.o`. The\n'
    printf 'column is the whole pipeline, comparable to the NURL native total beside\n'
    printf 'it and to the C and Rust wasm columns.\n\n'
    printf '| Benchmark | NURL `nurlc` | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |\n'
    printf '|---|---:|---:|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ |\n' \
        "$floor_cc_nurl_fe" "$floor_cc_nurl" "$floor_cc_nurl_wasm" \
        "$floor_cc_c" "$floor_cc_c_wasm" "$floor_cc_rust" "$floor_cc_rust_wasm"
    for i in "${!names[@]}"; do
        printf '| `%s` | %s | %s | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "${r_cc_nurl_fe[$i]}" "${r_cc_nurl[$i]}" "${r_cc_nurl_wasm[$i]}" \
            "${r_cc_c[$i]}" "${r_cc_c_wasm[$i]}" "${r_cc_rust[$i]}" "${r_cc_rust_wasm[$i]}"
    done
    printf '\n'

    printf '## 7. Correctness gate\n\n'
    printf 'Each row is timed only when all ten cells print the same line as the\n'
    printf 'native NURL binary. The interpreter is inside the gate, not beside it:\n'
    printf 'a runtime that gets the wrong answer quickly is not a fast runtime.\n\n'
    printf '| Benchmark | Output | Verdict |\n|---|---|---|\n'
    for i in "${!names[@]}"; do
        if [[ "${r_verified[$i]}" == true ]]; then
            printf '| `%s` | `%s` | identical: 3 languages x {native, JIT%s}, + NURL wasm `--no-gc-sections` |\n' \
                "${names[$i]}" "${r_checksum[$i]}" \
                "$( (( NWASM_ALL_LANGS )) && echo ', interpreter' || echo ', interpreter (NURL only)' )"
        else
            printf '| `%s` | — | **MISMATCH** — %s |\n' "${names[$i]}" "${r_detail[$i]}"
        fi
    done
    printf '\n'

    printf '## 8. Reading the numbers\n\n'
    printf '* Sections 1 and 3 are whole-process wall clock, so a cell near its\n'
    printf "  column's floor is mostly start-up — and on wasm, start-up includes the\n"
    printf '  runtime ingesting the module. Section 2 is where the steady-state\n'
    printf '  throughput ratio lives.\n'
    printf '* Every cell in a row computes the same thing, but not necessarily with\n'
    printf '  the same machine code. LLVM optimises for wasm and for x86-64\n'
    printf '  differently: wasm has no flags register, no `cmov`, and a JIT compiling\n'
    printf '  at load time cannot spend the time an offline `-O2` does. A ratio above\n'
    printf '  1 is that difference, not lost work.\n'
    printf '* The three languages share a corpus but not a runtime. A NURL module\n'
    printf "  carries NURL's allocator and string machinery; a Rust module carries\n"
    printf "  Rust's; a C module carries almost nothing. Section 4 is that difference\n"
    printf '  in bytes, and part of the floor row is the same difference in time.\n'
    printf "* The reference runtime's compiled-module cache is off. Its CLI enables\n"
    printf '  that cache by default, which would make a cell mean "Cranelift ran" or\n'
    printf '  "Cranelift did not run" depending on what happened to be in\n'
    printf '  `~/.cache/wasmtime` — including across the floor row, whose whole job is\n'
    printf '  to be subtracted from the others. Off, both runtimes are measured doing\n'
    printf '  the same work: read the module, translate it, run it. A deployment that\n'
    printf '  keeps the cache (or precompiles with `wasmtime compile`) pays the floor\n'
    printf '  once instead of every run — section 2 is the number that survives that.\n'
    printf '* `json_parse` reads `bench/data.json`, so every wasm run gets a `--dir .`\n'
    printf '  preopen. The other rows pay the same preopen cost and need nothing from\n'
    printf '  it, which keeps the column internally comparable.\n'
    printf '* Wall clock on a machine that was not quiesced drifts a few per cent\n'
    printf '  between runs, and more on a shared CI runner. Compare deltas between\n'
    printf '  runs of the same workflow, not absolutes across machines.\n'
}

if (( WRITE )); then
    mkdir -p "$(dirname "$JSON_OUT")" "$(dirname "$MD_OUT")"
    emit_json > "$JSON_OUT"
    emit_md   > "$MD_OUT"
    echo "wrote $JSON_OUT"
    echo "wrote $MD_OUT"
else
    emit_md
fi

# A mismatched row is a failure of the suite, not a slow benchmark.
for v in "${r_verified[@]}"; do
    [[ "$v" == true ]] || { echo "wasmbench.sh: at least one row failed the correctness gate" >&2; exit 1; }
done
