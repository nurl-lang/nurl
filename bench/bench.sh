#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  bench/bench.sh — the one benchmark runner.
#
#  Every benchmark in bench/manifest.tsv is implemented five times —
#  NURL, C, Rust, Node, Python — and every implementation prints one
#  line. This script compiles what needs compiling, gates the row on all
#  five printing the *same* line, then times them and writes two
#  artefacts:
#
#    bench/results/latest.json   machine-readable; the landing page's
#                                table is generated from this file at
#                                publish time (tools/gen-bench-table.mjs)
#    bench/RESULTS.md            the same run rendered for humans, with
#                                the compile-time and correctness tables
#                                the web page deliberately leaves out
#
#  It replaces the previous pair of runners (run.sh, which timed three
#  benchmarks in four languages, and run_micro.sh, which timed ten u64
#  kernels in three) — same corpus, one protocol, no benchmark measured
#  twice.
#
#  Usage:
#      ./bench/bench.sh                     # full suite, write both files
#      ./bench/bench.sh --quick             # 1 rep/cell, for a smoke test
#      ./bench/bench.sh --bench lcg --bench sieve
#      ./bench/bench.sh --reps 9 --budget-ms 20000
#      ./bench/bench.sh --stdout            # print the report, touch nothing
#
#  Requires nurlc (./build.sh), clang, rustc, node and python3. A missing
#  toolchain is a hard error: a table with a hole in it is worse than no
#  table, because the hole is invisible once the numbers are copied out.
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build"
MANIFEST="$BENCH/manifest.tsv"

# ── settings ─────────────────────────────────────────────────────
MAX_REPS=5            # timed runs per cell, at most
BUDGET_MS=8000        # per-cell time budget; a slow cell gets fewer reps
TIMEOUT_S=300         # per-run wall-clock cap
COMPILE_REPS=3        # timed compiles per compiled language
OPT="-O2"
JSON_OUT="$BENCH/results/latest.json"
MD_OUT="$BENCH/RESULTS.md"
WRITE=1
SELECTED=()

usage() { sed -n '4,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while (( $# > 0 )); do
    case "$1" in
        --bench)        SELECTED+=("$2"); shift 2 ;;
        --reps)         MAX_REPS="$2"; shift 2 ;;
        --budget-ms)    BUDGET_MS="$2"; shift 2 ;;
        --timeout)      TIMEOUT_S="$2"; shift 2 ;;
        --compile-reps) COMPILE_REPS="$2"; shift 2 ;;
        --json)         JSON_OUT="$2"; shift 2 ;;
        --md)           MD_OUT="$2"; shift 2 ;;
        --stdout)       WRITE=0; shift ;;
        --quick)        MAX_REPS=1; BUDGET_MS=1; COMPILE_REPS=1; shift ;;
        -h|--help)      usage 0 ;;
        *)              echo "bench.sh: unknown argument '$1'" >&2; usage 2 ;;
    esac
done

mkdir -p "$BUILD"

# ── toolchain detection ──────────────────────────────────────────
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
missing=()
[[ -x "$NURLC" && -f "$RUNTIME" ]] || missing+=("nurlc (run ./build.sh)")
command -v clang   >/dev/null || missing+=("clang")
command -v rustc   >/dev/null || missing+=("rustc")
command -v node    >/dev/null || missing+=("node")
command -v python3 >/dev/null || missing+=("python3")
if (( ${#missing[@]} > 0 )); then
    printf 'bench.sh: missing toolchain: %s\n' "${missing[*]}" >&2
    exit 1
fi

# Optional FFI libs the NURL runtime may have been built against — the
# same detection compiler/tests/run_tests.sh does, so the link line here
# matches a normal `nurl.sh` build byte for byte.
EXTRA_LIBS=""
for pair in "runtime.curl:libcurl" "runtime.openssl:openssl" "runtime.sqlite3:sqlite3" \
            "runtime.pq:libpq" "runtime.z:zlib" "runtime.zstd:libzstd"; do
    marker="${pair%%:*}"; pc="${pair##*:}"
    [[ -f "$ROOT/stdlib/$marker" ]] && EXTRA_LIBS="$EXTRA_LIBS $(pkg-config --libs "$pc" 2>/dev/null)"
done

NURL_VERSION="$("$NURLC" --version 2>/dev/null | head -1)"
[[ -n "$NURL_VERSION" ]] || NURL_VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null)"
CLANG_VERSION="$(clang --version | head -1)"
RUSTC_VERSION="$(rustc --version)"
NODE_VERSION="$(node --version)"
PYTHON_VERSION="$(python3 --version 2>&1)"

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
# One wall-clock reading in milliseconds, three decimals. Uses bash 5's
# $EPOCHREALTIME rather than forking `date` twice, which would add ~3 ms
# of fork+exec to every reading — larger than several of the cells.
# Prints FAIL on a non-zero exit and TIMEOUT when the cap is hit.
#
# Set TIME_STDOUT to capture the command's stdout into a file instead of
# discarding it — `nurlc` writes its LLVM IR there, so the compile stage
# has to keep it while still being timed.
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
# BUDGET_MS, capped at MAX_REPS. A 6 ms cell gets the full 5 runs for
# 30 ms; a 25-second Python cell gets one, because a second run buys
# noise reduction the reader cannot use and costs another 25 seconds.
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
# nurlc resolves `$ "stdlib/..."` imports relative to its working
# directory, so every compile and every run happens from $ROOT.
compile_nurl() {           # <src.nu> <outbase> -> "<frontend_ms> <total_ms>" or FAIL
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

compile_c() {              # <src.c> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.c.bin" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        # shellcheck disable=SC2086
        t="$(cd "$ROOT" && time_ms clang $OPT "$src" -lm -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

compile_rust() {           # <src.rs> <outbase> -> "<ms>" or FAIL
    local src="$1" bin="$2.rs.bin" out=() r t
    for ((r = 0; r < COMPILE_REPS; r++)); do
        t="$(cd "$ROOT" && time_ms rustc -C opt-level=2 "$src" -o "$bin")"
        [[ "$t" == FAIL || "$t" == TIMEOUT ]] && { echo FAIL; return 1; }
        out+=("$t")
    done
    median "${out[@]}"
}

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
    echo "bench.sh: no benchmarks selected" >&2
    exit 2
fi

# json_parse reads a generated fixture; make sure it exists before the
# gate runs, or four languages fail identically and the row looks fine.
[[ -f "$BENCH/data.json" ]] || python3 "$BENCH/gen_data.py"

# ── process-start-up floor ───────────────────────────────────────
# What each language costs for a program that does nothing. Subtract it
# from a cell to see the marginal cost of the benchmark itself; a row
# under ~10 ms is mostly this.
floor_dir="$BUILD/floor"
mkdir -p "$floor_dir"
printf '@ main → i {\n    ^ 0\n}\n'      > "$floor_dir/floor.nu"
printf 'int main(void) { return 0; }\n'  > "$floor_dir/floor.c"
printf 'fn main() {}\n'                  > "$floor_dir/floor.rs"
: > "$floor_dir/floor.py"
: > "$floor_dir/floor.js"

# The same compile path the benchmarks take, so the compile-time table
# has a floor to subtract too: for NURL that floor is the LTO link
# against stdlib/runtime.o, which every NURL binary pays whatever it does.
read -r floor_cc_nurl_fe floor_cc_nurl <<<"$(compile_nurl "$floor_dir/floor.nu" "$floor_dir/floor")"
floor_cc_c="$(compile_c "$floor_dir/floor.c" "$floor_dir/floor")"
floor_cc_rust="$(compile_rust "$floor_dir/floor.rs" "$floor_dir/floor")"

read -r floor_nurl _   <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.nurl.bin")"
read -r floor_c _      <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.c.bin")"
read -r floor_rust _   <<<"$(cd "$ROOT" && time_cell "$floor_dir/floor.rs.bin")"
read -r floor_node _   <<<"$(cd "$ROOT" && time_cell node "$floor_dir/floor.js")"
read -r floor_python _ <<<"$(cd "$ROOT" && time_cell python3 "$floor_dir/floor.py")"

# ── measure ──────────────────────────────────────────────────────
# Per-benchmark results, collected as parallel arrays (bash 3 has no
# nested structures and the report needs them in manifest order anyway).
r_checksum=(); r_verified=(); r_detail=()
r_nurl=(); r_c=(); r_rust=(); r_node=(); r_python=()
r_nurl_reps=(); r_c_reps=(); r_rust_reps=(); r_node_reps=(); r_python_reps=()
r_cc_nurl_fe=(); r_cc_nurl=(); r_cc_c=(); r_cc_rust=()

progress() { printf '\r\033[K  %-18s %s' "$1" "$2" >&2; }

for idx in "${!names[@]}"; do
    b="${names[$idx]}"

    progress "$b" "compiling…"
    read -r cc_fe cc_nurl <<<"$(compile_nurl "$BENCH/$b.nu" "$BUILD/$b")"
    cc_c="$(compile_c "$BENCH/$b.c" "$BUILD/$b")"
    cc_rust="$(compile_rust "$BENCH/$b.rs" "$BUILD/$b")"
    r_cc_nurl_fe+=("${cc_fe:-FAIL}"); r_cc_nurl+=("${cc_nurl:-FAIL}")
    r_cc_c+=("$cc_c"); r_cc_rust+=("$cc_rust")

    progress "$b" "verifying…"
    out_nurl="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.nurl.bin" 2>/dev/null)"
    out_c="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.c.bin" 2>/dev/null)"
    out_rust="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" "$BUILD/$b.rs.bin" 2>/dev/null)"
    out_node="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" node "$BENCH/$b.js" 2>/dev/null)"
    out_python="$(cd "$ROOT" && timeout "${TIMEOUT_S}s" python3 "$BENCH/$b.py" 2>/dev/null)"

    verified=true; detail=""
    for pair in "NURL:$out_nurl" "C:$out_c" "Rust:$out_rust" "Node:$out_node" "Python:$out_python"; do
        lang="${pair%%:*}"; got="${pair#*:}"
        [[ "$got" == "$out_nurl" ]] || verified=false
        [[ -n "$got" ]] || verified=false
        detail="$detail${detail:+, }$lang=${got:-<empty>}"
    done
    r_checksum+=("$out_nurl"); r_verified+=("$verified"); r_detail+=("$detail")

    if [[ "$verified" != true ]]; then
        printf '\r\033[K  %-18s MISMATCH — %s\n' "$b" "$detail" >&2
        r_nurl+=(SKIPPED); r_c+=(SKIPPED); r_rust+=(SKIPPED); r_node+=(SKIPPED); r_python+=(SKIPPED)
        r_nurl_reps+=(0); r_c_reps+=(0); r_rust_reps+=(0); r_node_reps+=(0); r_python_reps+=(0)
        continue
    fi

    progress "$b" "timing NURL…";   read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.nurl.bin")"
    r_nurl+=("$ms"); r_nurl_reps+=("$reps")
    progress "$b" "timing C…";      read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.c.bin")"
    r_c+=("$ms"); r_c_reps+=("$reps")
    progress "$b" "timing Rust…";   read -r ms reps <<<"$(cd "$ROOT" && time_cell "$BUILD/$b.rs.bin")"
    r_rust+=("$ms"); r_rust_reps+=("$reps")
    progress "$b" "timing Node…";   read -r ms reps <<<"$(cd "$ROOT" && time_cell node "$BENCH/$b.js")"
    r_node+=("$ms"); r_node_reps+=("$reps")
    progress "$b" "timing Python…"; read -r ms reps <<<"$(cd "$ROOT" && time_cell python3 "$BENCH/$b.py")"
    r_python+=("$ms"); r_python_reps+=("$reps")

    printf '\r\033[K  %-18s nurl %9s  c %9s  rust %9s  node %9s  python %9s\n' \
        "$b" "${r_nurl[$idx]}" "${r_c[$idx]}" "${r_rust[$idx]}" "${r_node[$idx]}" "${r_python[$idx]}" >&2
done
printf '\r\033[K' >&2

# ── emit ─────────────────────────────────────────────────────────
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
jnum() { [[ "$1" =~ ^[0-9.]+$ ]] && printf '%s' "$1" || printf 'null'; }

emit_json() {
    printf '{\n'
    printf '  "schema": 1,\n'
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
    printf '    "nurl": "%s",\n'   "$(jstr "$NURL_VERSION")"
    printf '    "c": "%s",\n'      "$(jstr "$CLANG_VERSION")"
    printf '    "rust": "%s",\n'   "$(jstr "$RUSTC_VERSION")"
    printf '    "node": "%s",\n'   "$(jstr "$NODE_VERSION")"
    printf '    "python": "%s"\n'  "$(jstr "$PYTHON_VERSION")"
    printf '  },\n'
    printf '  "settings": {\n'
    printf '    "opt": "%s",\n' "$(jstr "$OPT")"
    printf '    "max_reps": %s,\n' "$MAX_REPS"
    printf '    "budget_ms": %s,\n' "$BUDGET_MS"
    printf '    "timeout_s": %s,\n' "$TIMEOUT_S"
    printf '    "compile_reps": %s\n' "$COMPILE_REPS"
    printf '  },\n'
    printf '  "floor_ms": { "nurl": %s, "c": %s, "rust": %s, "node": %s, "python": %s },\n' \
        "$(jnum "$floor_nurl")" "$(jnum "$floor_c")" "$(jnum "$floor_rust")" \
        "$(jnum "$floor_node")" "$(jnum "$floor_python")"
    printf '  "floor_compile_ms": { "nurl_frontend": %s, "nurl": %s, "c": %s, "rust": %s },\n' \
        "$(jnum "$floor_cc_nurl_fe")" "$(jnum "$floor_cc_nurl")" \
        "$(jnum "$floor_cc_c")" "$(jnum "$floor_cc_rust")"
    printf '  "benchmarks": [\n'
    local i last=$(( ${#names[@]} - 1 ))
    for i in "${!names[@]}"; do
        printf '    {\n'
        printf '      "name": "%s",\n'     "$(jstr "${names[$i]}")"
        printf '      "blurb": "%s",\n'    "$(jstr "${blurbs[$i]}")"
        printf '      "measures": "%s",\n' "$(jstr "${shapes[$i]}")"
        printf '      "checksum": "%s",\n' "$(jstr "${r_checksum[$i]}")"
        printf '      "verified": %s,\n'   "${r_verified[$i]}"
        printf '      "run_ms": { "nurl": %s, "c": %s, "rust": %s, "node": %s, "python": %s },\n' \
            "$(jnum "${r_nurl[$i]}")" "$(jnum "${r_c[$i]}")" "$(jnum "${r_rust[$i]}")" \
            "$(jnum "${r_node[$i]}")" "$(jnum "${r_python[$i]}")"
        printf '      "reps": { "nurl": %s, "c": %s, "rust": %s, "node": %s, "python": %s },\n' \
            "${r_nurl_reps[$i]}" "${r_c_reps[$i]}" "${r_rust_reps[$i]}" \
            "${r_node_reps[$i]}" "${r_python_reps[$i]}"
        printf '      "compile_ms": { "nurl_frontend": %s, "nurl": %s, "c": %s, "rust": %s }\n' \
            "$(jnum "${r_cc_nurl_fe[$i]}")" "$(jnum "${r_cc_nurl[$i]}")" \
            "$(jnum "${r_cc_c[$i]}")" "$(jnum "${r_cc_rust[$i]}")"
        printf '    }%s\n' "$( (( i < last )) && echo ',' )"
    done
    printf '  ]\n'
    printf '}\n'
}

# Markdown cell: bold when this language is the fastest in its row.
mdcell() {
    local val="$1" best="$2"
    if [[ "$val" == "$best" ]]; then printf '**%s**' "$val"; else printf '%s' "$val"; fi
}

fastest_of() {
    printf '%s\n' "$@" | awk 'BEGIN { best = "" } /^[0-9.]+$/ { if (best == "" || $1 + 0 < best + 0) best = $1 } END { print best }'
}

emit_md() {
    printf '# Benchmark results — NURL vs C vs Rust vs Node vs Python\n\n'
    printf 'Generated `%s` by `bench/bench.sh`. **Do not edit by hand** — the next\n' "$NOW"
    printf 'run overwrites it. The machine-readable form of this same run is\n'
    printf '[`results/latest.json`](results/latest.json), which is what the landing\n'
    printf 'page renders its table from.\n\n'

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
    printf '| Node | %s |\n' "$NODE_VERSION"
    printf '| Python | %s |\n' "$PYTHON_VERSION"
    printf '\n'
    printf '| Setting | Value |\n|---|---|\n'
    printf '| Optimisation | NURL/C `clang %s`, Rust `-C opt-level=2` |\n' "$OPT"
    printf '| Timed runs per cell | up to %s, adaptive: as many as fit in %s ms |\n' "$MAX_REPS" "$BUDGET_MS"
    printf '| Timed compiles per cell | %s (median) |\n' "$COMPILE_REPS"
    printf '| Per-run timeout | %s s |\n' "$TIMEOUT_S"
    printf '\n'

    printf '## 1. Run time (median wall clock, ms — lower is better)\n\n'
    printf 'Whole-process wall clock, start-up included. Every implementation of a\n'
    printf 'row prints the same line (section 3), so these are five timings of the\n'
    printf 'same computation. **Bold** is the fastest cell in the row.\n\n'
    printf '| Benchmark | NURL | C | Rust | Node | Python |\n|---|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _%s_ | _%s_ | _%s_ |\n' \
        "$floor_nurl" "$floor_c" "$floor_rust" "$floor_node" "$floor_python"
    local i best
    for i in "${!names[@]}"; do
        best="$(fastest_of "${r_nurl[$i]}" "${r_c[$i]}" "${r_rust[$i]}" "${r_node[$i]}" "${r_python[$i]}")"
        printf '| `%s` | %s | %s | %s | %s | %s |\n' "${names[$i]}" \
            "$(mdcell "${r_nurl[$i]}" "$best")" "$(mdcell "${r_c[$i]}" "$best")" \
            "$(mdcell "${r_rust[$i]}" "$best")" "$(mdcell "${r_node[$i]}" "$best")" \
            "$(mdcell "${r_python[$i]}" "$best")"
    done
    printf '\n'

    printf '## 2. Compile time (median, ms)\n\n'
    printf "NURL's compile is two stages: \`nurlc\` emits LLVM IR, then \`clang\`\n"
    printf 'lowers and links it against `stdlib/runtime.o`. **NURL total** is the\n'
    printf 'number comparable to the C and Rust columns. The floor row is what each\n'
    printf 'toolchain costs for a program that does nothing — for NURL that is\n'
    printf 'dominated by the LTO link every NURL binary pays for, so subtract it to\n'
    printf 'read the marginal cost of the benchmark itself. Node and Python have no\n'
    printf 'column here: they compile at run time, inside their own cells above.\n\n'
    printf '| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |\n'
    printf '|---|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _**%s**_ | _%s_ | _%s_ |\n' \
        "$floor_cc_nurl_fe" \
        "$(awk -v t="$floor_cc_nurl" -v f="$floor_cc_nurl_fe" \
            'BEGIN { if (t ~ /^[0-9.]+$/ && f ~ /^[0-9.]+$/) printf "%.3f", t - f; else print "n/a" }')" \
        "$floor_cc_nurl" "$floor_cc_c" "$floor_cc_rust"
    for i in "${!names[@]}"; do
        local link
        link="$(awk -v t="${r_cc_nurl[$i]}" -v f="${r_cc_nurl_fe[$i]}" \
            'BEGIN { if (t ~ /^[0-9.]+$/ && f ~ /^[0-9.]+$/) printf "%.3f", t - f; else print "n/a" }')"
        printf '| `%s` | %s | %s | **%s** | %s | %s |\n' "${names[$i]}" \
            "${r_cc_nurl_fe[$i]}" "$link" "${r_cc_nurl[$i]}" "${r_cc_c[$i]}" "${r_cc_rust[$i]}"
    done
    printf '\n'

    printf '## 3. Correctness gate\n\n'
    printf 'Each row is timed only when all five implementations print the same\n'
    printf 'line. A speed number for a program computing something else is worthless,\n'
    printf 'so a mismatch drops the row out of the tables above rather than being\n'
    printf 'reported as a fast cell.\n\n'
    printf '| Benchmark | Output | Verdict |\n|---|---|---|\n'
    for i in "${!names[@]}"; do
        if [[ "${r_verified[$i]}" == true ]]; then
            printf '| `%s` | `%s` | identical across 5 languages |\n' "${names[$i]}" "${r_checksum[$i]}"
        else
            printf '| `%s` | — | **MISMATCH** — %s |\n' "${names[$i]}" "${r_detail[$i]}"
        fi
    done
    printf '\n'

    printf '## 4. Reading the numbers\n\n'
    printf '* A cell near the floor row is mostly process start-up, dynamic linking\n'
    printf '  and page faults rather than the benchmark. The rows worth comparing are\n'
    printf '  the ones in the tens of milliseconds and up.\n'
    printf '* All three compiled back ends are LLVM-based and all three are allowed to\n'
    printf '  be clever: LLVM will fold an affine recurrence or unroll a loop by a\n'
    printf '  different factor in each language. A cell measures optimised throughput\n'
    printf '  of the same algorithm, not the source-level iteration count.\n'
    printf '* Nine of the fifteen benchmarks are defined over 64-bit unsigned integers.\n'
    printf '  Python has arbitrary-precision integers and masks; JS has no 64-bit\n'
    printf '  integer at all, so those rows use `BigInt` where the algorithm genuinely\n'
    printf '  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each\n'
    printf '  file says which and why. That gap *is* part of what this table reports.\n'
    printf '* `nbody` is the counterweight to the row above, and the only row defined\n'
    printf "  over IEEE-754 doubles rather than integers. That is the type JavaScript\n"
    printf '  does have — its one numeric type is the double — so Node runs the same\n'
    printf '  arithmetic as the compiled backends with no representation tax, and lands\n'
    printf '  near 2x C instead of the 30-50x the BigInt rows cost it. It is also the\n'
    printf "  only row whose critical path runs through the FPU's long-latency sqrt and\n"
    printf '  divide units rather than the integer ALU. All five ports use the same\n'
    printf '  operation order and the same struct-of-arrays layout, so the checksum —\n'
    printf "  the final energy's bit pattern — is exact across all five.\n"
    printf '* `json_parse` is the one row whose gate is "every parser accepted the\n'
    printf '  document" rather than a structural checksum: each language uses the\n'
    printf '  parser in its own box (Python `json`, Node `JSON.parse`, NURL\n'
    printf "  \`stdlib/ext/json.nu\`), and C and Rust — whose boxes are empty — carry a\n"
    printf '  small hand-written recursive-descent parser in the benchmark file.\n'
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
    [[ "$v" == true ]] || { echo "bench.sh: at least one row failed the correctness gate" >&2; exit 1; }
done
