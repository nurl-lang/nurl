#!/usr/bin/env bash
# bench/run_micro.sh — compile-time + run-time comparison for the u64
# micro-benchmark set (the `benchmark-contract:` files) across NURL, C
# and Rust.
#
# Two phases, in this order:
#   1. compile every source in every available language, timing each
#      compiler invocation, then write the compile-time table;
#   2. run every binary, timing each, then append the run-time table.
#
# Both phases land in the same Markdown report:
#   bench/bench_results_YYYYMMDDHHMM.md
#
# Between the phases the script runs a correctness gate: each language
# is also built in "verify" mode, which dumps the 8 little-endian
# checksum bytes to stdout, and the three dumps must be byte-identical.
# A benchmark whose languages disagree is still timed, but the report
# marks it — a speed number for a program computing the wrong thing is
# worthless.
#
# Usage:
#   ./bench/run_micro.sh                       # defaults below
#   ./bench/run_micro.sh --reps 9              # 9 timed runs per cell
#   ./bench/run_micro.sh --compile-reps 5      # 5 timed compiles per cell
#   ./bench/run_micro.sh --bench hash_join     # one benchmark only
#   ./bench/run_micro.sh --timeout 300         # raise the per-run cap
#   ./bench/run_micro.sh --out /tmp/report.md  # explicit report path
#
# Tools: build/nurlc + stdlib/runtime.o (NURL), clang (C, and NURL's
# backend), rustc (Rust). A missing toolchain renders as `n/a` instead
# of failing the suite.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build/micro"

RUN_REPS=5
COMPILE_REPS=3
RUN_TIMEOUT=120          # seconds per run; SIGKILL, so 137 == timeout
BENCH_FILTER=""
OUT=""

while (( $# > 0 )); do
    case "$1" in
        --reps)         RUN_REPS="$2"; shift 2 ;;
        --compile-reps) COMPILE_REPS="$2"; shift 2 ;;
        --timeout)      RUN_TIMEOUT="$2"; shift 2 ;;
        --bench)        BENCH_FILTER="$2"; shift 2 ;;
        --out)          OUT="$2"; shift 2 ;;
        -h|--help)      sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)              echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$BUILD"
[[ -z "$OUT" ]] && OUT="$BENCH/bench_results_$(date +%Y%m%d%H%M).md"

# ── roster ───────────────────────────────────────────────────────
# name|nu|c|rs|note — an empty language field means that language has no
# peer file; the note, when present, is reproduced in the report.
ROSTER=(
    "affine_mix|affine_mix.nu|affine_mix.c|affine_mix.rs|"
    "stream_lcg|stream_lcg.nu|stream_lcg.c|stream_lcg.rs|"
    "ring_write|ring_write.nu|ring_write.c|ring_write.rs|"
    "packet_classifier|packet_classifier.nu|packet_classifier.c|packet_classifier.rs|"
    "histogram_bins|histogram_bins.nu|histogram_bins.c|histogram_bins.rs|the set is named \`histogram_bins\` rather than \`histogram\` because \`bench/histogram.{nu,py,rs,js}\` is an older, unrelated benchmark (highest single-digit count in a string)."
    "prefix_scan|prefix_scan.nu|prefix_scan.c|prefix_scan.rs|"
    "binary_search|binary_search.nu|binary_search.c|binary_search.rs|"
    "sort_window|sort_window.nu|sort_window.c|sort_window.rs|"
    "bloom_filter|bloom_filter.nu|bloom_filter.c|bloom_filter.rs|"
    "hash_join|hash_join.nu|hash_join.c|hash_join.rs|"
)

# ── toolchain detection ──────────────────────────────────────────
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
CLANG="${CLANG:-clang}"
RUSTC="${RUSTC:-rustc}"

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_c=0;    command -v "$CLANG" >/dev/null && have_c=1
have_rs=0;   command -v "$RUSTC" >/dev/null && have_rs=1
(( have_nurl && ! have_c )) && have_nurl=0   # nurlc emits IR; clang lowers it

# Optimisation flags. NURL's line is the one nurl.sh uses for a release
# build: -flto is not a tuning choice, stdlib/runtime.o *is* LLVM
# bitcode and will not link without it.
#
# Why the two stages are driven directly instead of through `nurl.sh`:
# the driver runs the same `nurlc` and the same `clang` line and produces
# a byte-identical binary, but it first probes the environment — link
# probes against -lsqlite3, -lzstd and friends to decide which optional
# libraries exist. That is ~200 ms of fixed cost per invocation, the same
# for every input, and it is environment detection rather than
# compilation of the program. Charging it to NURL's compile column
# against a bare `clang x.c` (which has no analogue) would measure the
# wrong thing. Anyone reproducing a single binary by hand with `nurl.sh`
# gets the same output, just ~200 ms later.
NURL_LL_FLAGS=(-O2 -flto -Wl,--as-needed)
C_FLAGS=(-O2)
RS_FLAGS=(-O)

# ── timing primitives ────────────────────────────────────────────
# $EPOCHREALTIME avoids two `date` forks per measurement (~1.5 ms each,
# which is a real fraction of a 30 ms cell).
now_us() {
    local t=$EPOCHREALTIME
    local s=${t%.*}
    local u=${t#*.}
    echo $(( s * 1000000 + 10#$u ))
}

# median_us <us...> → median microseconds, or the first sentinel found
# (FAIL / TIMEOUT propagate: one broken sample invalidates the cell).
median_us() {
    local a
    for a in "$@"; do
        [[ "$a" == FAIL    ]] && { echo FAIL; return; }
        [[ "$a" == TIMEOUT ]] && { echo TIMEOUT; return; }
    done
    printf '%s\n' "$@" | sort -n | awk '{v[NR]=$1} END{print (NR%2) ? v[(NR+1)/2] : v[NR/2]}'
}

# ms <us> → milliseconds with one decimal, sentinels passed through.
ms() {
    case "$1" in
        FAIL|TIMEOUT|n/a) echo "$1" ;;
        *) awk -v u="$1" 'BEGIN{printf "%.1f", u/1000}' ;;
    esac
}

# ratio <a_us> <b_us> → "1.42×", or "—" when either side is not a number.
ratio() {
    case "$1$2" in
        *FAIL*|*TIMEOUT*|*n/a*) echo "—"; return ;;
    esac
    (( $2 == 0 )) && { echo "—"; return; }
    awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f×", a/b}'
}

# time_cmd <us_var_name> <cmd...> — run once, store elapsed µs (or the
# FAIL sentinel) in the named variable. stdout/stderr go to $LOG.
LOG="$BUILD/last.log"
#
# The internal locals are underscore-prefixed on purpose: a bash nameref
# resolves in the *current* scope, so a local named `ec` here would
# capture a caller that passed the name `ec` and silently write to the
# local instead of the caller's variable.
time_cmd() {
    local -n _out="$1"; shift
    local _t0 _t1 _rc
    _t0=$(now_us)
    "$@" > "$LOG" 2>&1
    _rc=$?
    _t1=$(now_us)
    (( _rc == 0 )) && _out=$(( _t1 - _t0 )) || _out=FAIL
}

# time_run <us_var_name> <ec_var_name> <cmd...> — like time_cmd but a
# non-zero exit is expected: these benchmarks encode `checksum & 0x7f`
# in their exit status. Only a SIGKILL from `timeout` (137) is a
# failure, and 137 cannot collide with a checksum (which is ≤ 127).
time_run() {
    local -n _us="$1" _ec="$2"; shift 2
    local _t0 _t1 _rc
    _t0=$(now_us)
    timeout -s KILL "${RUN_TIMEOUT}s" "$@" > /dev/null 2>&1
    _rc=$?
    _t1=$(now_us)
    _ec=$_rc
    if (( _rc == 137 )); then _us=TIMEOUT
    elif (( _rc > 127 )); then _us=FAIL
    else _us=$(( _t1 - _t0 ))
    fi
}

# ── phase 1: compile ─────────────────────────────────────────────
declare -A NU_FRONT NU_BACK NU_TOTAL C_US RS_US
declare -A NU_BIN C_BIN RS_BIN
declare -A NU_VBIN C_VBIN RS_VBIN
declare -A ERR NOTE
NAMES=()

for entry in "${ROSTER[@]}"; do
    IFS='|' read -r name nu c rs note <<< "$entry"
    [[ -n "$BENCH_FILTER" && "$name" != "$BENCH_FILTER" ]] && continue
    NAMES+=("$name")
    NOTE[$name]="$note"
    NU_FRONT[$name]=n/a; NU_BACK[$name]=n/a; NU_TOTAL[$name]=n/a
    C_US[$name]=n/a;     RS_US[$name]=n/a
    NU_BIN[$name]="";    C_BIN[$name]="";    RS_BIN[$name]=""
    NU_VBIN[$name]="";   C_VBIN[$name]="";   RS_VBIN[$name]=""
    ERR[$name]=""

    # ── NURL: nurlc (.nu → .ll) then clang (.ll + runtime → binary).
    # nurlc resolves `$`-imports relative to its CWD, so it runs from
    # $ROOT even though these files import nothing.
    if (( have_nurl )) && [[ -n "$nu" && -f "$BENCH/$nu" ]]; then
        local_front=(); local_back=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s compile nurl %d/%d\r' "$name" "$((r+1))" "$COMPILE_REPS" >&2
            rm -f "$BUILD/$name.ll" "$BUILD/${name}_nu"
            t0=$(now_us)
            ( cd "$ROOT" && "$NURLC" "$BENCH/$nu" > "$BUILD/$name.ll" 2> "$BUILD/$name.nurlc.err" )
            ec=$?
            t1=$(now_us)
            if (( ec != 0 )); then
                local_front=(FAIL); local_back=(FAIL)
                ERR[$name]="nurlc: $(head -1 "$BUILD/$name.nurlc.err")"
                break
            fi
            local_front+=( $(( t1 - t0 )) )
            t0=$(now_us)
            "$CLANG" "${NURL_LL_FLAGS[@]}" "$BUILD/$name.ll" "$RUNTIME" \
                     -lm -lpthread -o "$BUILD/${name}_nu" \
                     > "$BUILD/$name.clang.err" 2>&1
            ec=$?
            t1=$(now_us)
            if (( ec != 0 )); then
                local_back=(FAIL)
                ERR[$name]="clang: $(grep -m1 -i error "$BUILD/$name.clang.err")"
                break
            fi
            local_back+=( $(( t1 - t0 )) )
        done
        f=$(median_us "${local_front[@]}")
        b=$(median_us "${local_back[@]}")
        NU_FRONT[$name]=$f; NU_BACK[$name]=$b
        if [[ "$f" == FAIL || "$b" == FAIL ]]; then
            NU_TOTAL[$name]=FAIL
        else
            NU_TOTAL[$name]=$(( f + b ))
            NU_BIN[$name]="$BUILD/${name}_nu"
        fi
    fi

    # ── C: one clang invocation.
    if (( have_c )) && [[ -n "$c" && -f "$BENCH/$c" ]]; then
        samples=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s compile c    %d/%d\r' "$name" "$((r+1))" "$COMPILE_REPS" >&2
            rm -f "$BUILD/${name}_c"
            time_cmd one "$CLANG" "${C_FLAGS[@]}" "$BENCH/$c" -o "$BUILD/${name}_c"
            [[ "$one" == FAIL ]] && { ERR[$name]="cc: $(grep -m1 -i error "$LOG")"; samples=(FAIL); break; }
            samples+=("$one")
        done
        C_US[$name]=$(median_us "${samples[@]}")
        [[ "${C_US[$name]}" != FAIL ]] && C_BIN[$name]="$BUILD/${name}_c"
    fi

    # ── Rust: one rustc invocation.
    if (( have_rs )) && [[ -n "$rs" && -f "$BENCH/$rs" ]]; then
        samples=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s compile rust %d/%d\r' "$name" "$((r+1))" "$COMPILE_REPS" >&2
            rm -f "$BUILD/${name}_rs"
            time_cmd one "$RUSTC" "${RS_FLAGS[@]}" "$BENCH/$rs" -o "$BUILD/${name}_rs"
            [[ "$one" == FAIL ]] && { ERR[$name]="rustc: $(grep -m1 -E '^error' "$LOG")"; samples=(FAIL); break; }
            samples+=("$one")
        done
        RS_US[$name]=$(median_us "${samples[@]}")
        [[ "${RS_US[$name]}" != FAIL ]] && RS_BIN[$name]="$BUILD/${name}_rs"
    fi

    # ── verify-mode builds (untimed; the correctness gate only).
    # NURL needs no second build: its checksum dump is behind a
    # `--verify` argument rather than a compile-time switch.
    [[ -n "${NU_BIN[$name]}" ]] && NU_VBIN[$name]="${NU_BIN[$name]}"
    if [[ -n "${C_BIN[$name]}" ]]; then
        "$CLANG" "${C_FLAGS[@]}" -DBENCH_VERIFY "$BENCH/$c" -o "$BUILD/${name}_c_v" 2>/dev/null \
            && C_VBIN[$name]="$BUILD/${name}_c_v"
    fi
    if [[ -n "${RS_BIN[$name]}" ]]; then
        "$RUSTC" "${RS_FLAGS[@]}" --cfg bench_verify "$BENCH/$rs" -o "$BUILD/${name}_rs_v" 2>/dev/null \
            && RS_VBIN[$name]="$BUILD/${name}_rs_v"
    fi
done
printf '                                                  \r' >&2

# ── fixed-cost floor ─────────────────────────────────────────────
# What each toolchain costs for a program that does nothing. NURL's
# floor is dominated by the LTO link against stdlib/runtime.o, which
# every NURL binary pays whether or not it calls into the runtime;
# subtracting the floor from a cell gives its marginal compile cost.
FL_NU_F=n/a; FL_NU_B=n/a; FL_NU_T=n/a; FL_C=n/a; FL_RS=n/a
printf '@ main → i {\n    ^ 0\n}\n'      > "$BUILD/_floor.nu"
printf 'int main(void) { return 0; }\n'  > "$BUILD/_floor.c"
printf 'fn main() {}\n'                  > "$BUILD/_floor.rs"

if (( have_nurl )); then
    f_samples=(); b_samples=()
    for ((r=0; r<COMPILE_REPS; r++)); do
        printf '  …%-18s compile nurl %d/%d\r' "(floor)" "$((r+1))" "$COMPILE_REPS" >&2
        rm -f "$BUILD/_floor.ll" "$BUILD/_floor_nu"
        t0=$(now_us)
        ( cd "$ROOT" && "$NURLC" "$BUILD/_floor.nu" > "$BUILD/_floor.ll" 2>/dev/null )
        t1=$(now_us)
        f_samples+=( $(( t1 - t0 )) )
        t0=$(now_us)
        "$CLANG" "${NURL_LL_FLAGS[@]}" "$BUILD/_floor.ll" "$RUNTIME" \
                 -lm -lpthread -o "$BUILD/_floor_nu" > /dev/null 2>&1
        t1=$(now_us)
        b_samples+=( $(( t1 - t0 )) )
    done
    FL_NU_F=$(median_us "${f_samples[@]}")
    FL_NU_B=$(median_us "${b_samples[@]}")
    FL_NU_T=$(( FL_NU_F + FL_NU_B ))
fi
if (( have_c )); then
    samples=()
    for ((r=0; r<COMPILE_REPS; r++)); do
        printf '  …%-18s compile c    %d/%d\r' "(floor)" "$((r+1))" "$COMPILE_REPS" >&2
        time_cmd one "$CLANG" "${C_FLAGS[@]}" "$BUILD/_floor.c" -o "$BUILD/_floor_c"
        samples+=("$one")
    done
    FL_C=$(median_us "${samples[@]}")
fi
if (( have_rs )); then
    samples=()
    for ((r=0; r<COMPILE_REPS; r++)); do
        printf '  …%-18s compile rust %d/%d\r' "(floor)" "$((r+1))" "$COMPILE_REPS" >&2
        time_cmd one "$RUSTC" "${RS_FLAGS[@]}" "$BUILD/_floor.rs" -o "$BUILD/_floor_rs"
        samples+=("$one")
    done
    FL_RS=$(median_us "${samples[@]}")
fi
printf '                                                  \r' >&2

# ── report header + compile-time table ───────────────────────────
cpu=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
[[ -z "$cpu" ]] && cpu="unknown"
cores=$(nproc 2>/dev/null || echo "?")
nurl_ver=$("$NURLC" --version 2>/dev/null | head -1)
c_ver=$( (( have_c ))  && "$CLANG" --version 2>/dev/null | head -1 || echo "not installed")
rs_ver=$( (( have_rs )) && "$RUSTC" --version 2>/dev/null | head -1 || echo "not installed")

{
printf '# NURL vs C vs Rust — u64 micro-benchmark set\n\n'
printf 'Generated `%s` by `bench/run_micro.sh`.\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '## Environment\n\n'
printf '| Item | Value |\n|---|---|\n'
printf '| Host | `%s` |\n' "$(uname -n)"
printf '| Kernel | `%s` |\n' "$(uname -sr)"
printf '| CPU | %s (%s logical cores) |\n' "$cpu" "$cores"
printf '| NURL | `%s` |\n' "${nurl_ver:-build/nurlc}"
printf '| C | %s |\n' "$c_ver"
printf '| Rust | %s |\n' "$rs_ver"
printf '\n'
printf '| Language | Compile command |\n|---|---|\n'
printf '| NURL | `build/nurlc x.nu > x.ll` then `clang %s x.ll stdlib/runtime.o -lm -lpthread -o x` |\n' "${NURL_LL_FLAGS[*]}"
printf '| C | `clang %s x.c -o x` |\n' "${C_FLAGS[*]}"
printf '| Rust | `rustc %s x.rs -o x` |\n' "${RS_FLAGS[*]}"
printf '\n'
printf '| Setting | Value |\n|---|---|\n'
printf '| Timed compiles per cell | %d (median) |\n' "$COMPILE_REPS"
printf '| Timed runs per cell | %d (median) |\n' "$RUN_REPS"
printf '| Per-run timeout | %d s |\n' "$RUN_TIMEOUT"
printf '\n'

printf '## 1. Compile time (median, ms)\n\n'
printf 'NURL is split into its two stages: `nurlc` emits LLVM IR, then `clang`\n'
printf 'lowers that IR and links it against the runtime. `NURL total` is the\n'
printf 'number comparable to the C and Rust columns — those are single\n'
printf 'invocations that also do codegen and linking.\n\n'
printf 'The first row is the floor: what each toolchain costs for a program that\n'
printf 'does nothing. For NURL that floor is dominated by the LTO link against\n'
printf '`stdlib/runtime.o` — a fixed cost every NURL binary pays. Subtract the\n'
printf 'floor from a cell to see the marginal compile cost of that benchmark.\n\n'
printf '| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |\n'
printf '|---|---:|---:|---:|---:|---:|\n'
printf '| _(floor: empty program)_ | _%s_ | _%s_ | _**%s**_ | _%s_ | _%s_ |\n' \
    "$(ms "$FL_NU_F")" "$(ms "$FL_NU_B")" "$(ms "$FL_NU_T")" "$(ms "$FL_C")" "$(ms "$FL_RS")"
} > "$OUT"

# The totals row sums only the benchmarks that exist in all three
# languages, so the three columns stay comparable to each other.
sum_nu=0; sum_c=0; sum_rs=0; n_common=0
for name in "${NAMES[@]}"; do
    printf '| `%s` | %s | %s | **%s** | %s | %s |\n' \
        "$name" "$(ms "${NU_FRONT[$name]}")" "$(ms "${NU_BACK[$name]}")" \
        "$(ms "${NU_TOTAL[$name]}")" "$(ms "${C_US[$name]}")" "$(ms "${RS_US[$name]}")"
    if [[ "${NU_TOTAL[$name]}" =~ ^[0-9]+$ && "${C_US[$name]}" =~ ^[0-9]+$ && "${RS_US[$name]}" =~ ^[0-9]+$ ]]; then
        sum_nu=$(( sum_nu + NU_TOTAL[$name] ))
        sum_c=$(( sum_c + C_US[$name] ))
        sum_rs=$(( sum_rs + RS_US[$name] ))
        n_common=$(( n_common + 1 ))
    fi
done >> "$OUT"
{
printf '| **sum over the %d rows built by all three** | | | **%s** | %s | %s |\n' \
    "$n_common" "$(ms "$sum_nu")" "$(ms "$sum_c")" "$(ms "$sum_rs")"
printf '\n`n/a` = no source file in that language. `FAIL` = the compiler'
printf ' rejected it (see Notes).\n'
} >> "$OUT"

echo "compile phase done → $OUT" >&2

# ── correctness gate ─────────────────────────────────────────────
declare -A SUM_NU SUM_C SUM_RS VERDICT EXPECT_EC
for name in "${NAMES[@]}"; do
    printf '  …%-18s verify\r' "$name" >&2
    SUM_NU[$name]=""; SUM_C[$name]=""; SUM_RS[$name]=""
    [[ -n "${NU_VBIN[$name]}" ]] && SUM_NU[$name]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${NU_VBIN[$name]}" --verify | xxd -p)
    [[ -n "${C_VBIN[$name]}"  ]] && SUM_C[$name]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${C_VBIN[$name]}" | xxd -p)
    [[ -n "${RS_VBIN[$name]}" ]] && SUM_RS[$name]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${RS_VBIN[$name]}" | xxd -p)

    present=(); for s in "${SUM_NU[$name]}" "${SUM_C[$name]}" "${SUM_RS[$name]}"; do
        [[ -n "$s" ]] && present+=("$s")
    done
    if (( ${#present[@]} == 0 )); then
        VERDICT[$name]="no build"
        EXPECT_EC[$name]=""
    else
        agree=1
        for s in "${present[@]}"; do [[ "$s" != "${present[0]}" ]] && agree=0; done
        if (( ${#present[@]} == 1 )); then VERDICT[$name]="single language"
        elif (( agree )); then VERDICT[$name]="identical"
        else VERDICT[$name]="**MISMATCH**"
        fi
        # The exit status every language must report: checksum & 0x7f,
        # i.e. the low byte of the little-endian dump masked to 7 bits.
        EXPECT_EC[$name]=$(( 0x${present[0]:0:2} & 0x7f ))
    fi
done
printf '                                                  \r' >&2

{
printf '\n## 2. Correctness gate\n\n'
printf 'Every language writes the same 8 little-endian checksum bytes when built\n'
printf 'in verify mode (`-DBENCH_VERIFY` for C, `--cfg bench_verify` for Rust,\n'
printf '`--verify` on the command line for NURL). A timing number below is only\n'
printf 'meaningful for a row that says `identical`.\n\n'
printf '| Benchmark | Checksum (LE hex) | NURL | C | Rust | Verdict |\n'
printf '|---|---|:-:|:-:|:-:|---|\n'
for name in "${NAMES[@]}"; do
    mark() { [[ -z "$1" ]] && echo "n/a" || { [[ "$1" == "$2" ]] && echo "✓" || echo "✗"; }; }
    ref=""
    for s in "${SUM_NU[$name]}" "${SUM_C[$name]}" "${SUM_RS[$name]}"; do
        [[ -n "$s" ]] && { ref="$s"; break; }
    done
    printf '| `%s` | `%s` | %s | %s | %s | %s |\n' "$name" "${ref:---}" \
        "$(mark "${SUM_NU[$name]}" "$ref")" \
        "$(mark "${SUM_C[$name]}" "$ref")" \
        "$(mark "${SUM_RS[$name]}" "$ref")" \
        "${VERDICT[$name]}"
done
} >> "$OUT"

# ── phase 2: run ─────────────────────────────────────────────────
declare -A RUN_NU RUN_C RUN_RS EC_NOTE
for name in "${NAMES[@]}"; do
    RUN_NU[$name]=n/a; RUN_C[$name]=n/a; RUN_RS[$name]=n/a; EC_NOTE[$name]=""
    for lang in nu c rs; do
        case $lang in
            nu) bin="${NU_BIN[$name]}"; args=() ;;
            c)  bin="${C_BIN[$name]}";  args=() ;;
            rs) bin="${RS_BIN[$name]}"; args=() ;;
        esac
        [[ -z "$bin" ]] && continue
        samples=()
        for ((r=0; r<RUN_REPS; r++)); do
            printf '  …%-18s run %-4s %d/%d\r' "$name" "$lang" "$((r+1))" "$RUN_REPS" >&2
            time_run one ec "$bin" "${args[@]}"
            samples+=("$one")
            # The exit status carries checksum & 0x7f — cross-check it
            # against the verify dump, so a run-phase regression cannot
            # hide behind a passing gate.
            if [[ "$one" != TIMEOUT && "$one" != FAIL && -n "${EXPECT_EC[$name]}" ]]; then
                (( ec != EXPECT_EC[$name] )) && \
                    EC_NOTE[$name]="${EC_NOTE[$name]}${lang} exit=$ec (expected ${EXPECT_EC[$name]}); "
            fi
        done
        med=$(median_us "${samples[@]}")
        case $lang in
            nu) RUN_NU[$name]=$med ;;
            c)  RUN_C[$name]=$med ;;
            rs) RUN_RS[$name]=$med ;;
        esac
    done
done
printf '                                                  \r' >&2

{
printf '\n## 3. Run time (median, ms)\n\n'
printf 'Wall clock of the whole process, including start-up. These binaries\n'
printf 'print nothing and return `checksum & 0x7f` as their exit status, so no\n'
printf 'I/O is being measured. The last two columns are NURL relative to the\n'
printf 'peer — below `1.00×` NURL is faster.\n\n'
printf '| Benchmark | NURL | C | Rust | NURL / C | NURL / Rust |\n'
printf '|---|---:|---:|---:|---:|---:|\n'
} >> "$OUT"

r_nu=0; r_c=0; r_rs=0; r_common=0
for name in "${NAMES[@]}"; do
    printf '| `%s` | %s | %s | %s | %s | %s |\n' "$name" \
        "$(ms "${RUN_NU[$name]}")" "$(ms "${RUN_C[$name]}")" "$(ms "${RUN_RS[$name]}")" \
        "$(ratio "${RUN_NU[$name]}" "${RUN_C[$name]}")" \
        "$(ratio "${RUN_NU[$name]}" "${RUN_RS[$name]}")"
    if [[ "${RUN_NU[$name]}" =~ ^[0-9]+$ && "${RUN_C[$name]}" =~ ^[0-9]+$ && "${RUN_RS[$name]}" =~ ^[0-9]+$ ]]; then
        r_nu=$(( r_nu + RUN_NU[$name] ))
        r_c=$(( r_c + RUN_C[$name] ))
        r_rs=$(( r_rs + RUN_RS[$name] ))
        r_common=$(( r_common + 1 ))
    fi
done >> "$OUT"
{
printf '| **sum over the %d rows run in all three** | %s | %s | %s | %s | %s |\n' \
    "$r_common" "$(ms "$r_nu")" "$(ms "$r_c")" "$(ms "$r_rs")" \
    "$(ratio "$r_nu" "$r_c")" "$(ratio "$r_nu" "$r_rs")"

# ── notes ────────────────────────────────────────────────────────
printf '\n## 4. Notes\n\n'
problems=0
for name in "${NAMES[@]}"; do
    [[ -n "${ERR[$name]}" ]] && { printf -- '- `%s`: %s\n' "$name" "${ERR[$name]}"; problems=1; }
    [[ -n "${EC_NOTE[$name]}" ]] && { printf -- '- `%s`: exit-status cross-check failed — %s\n' "$name" "${EC_NOTE[$name]}"; problems=1; }
    [[ "${VERDICT[$name]}" == '**MISMATCH**' ]] && { printf -- '- `%s`: the languages disagree on the checksum — treat its timings as void.\n' "$name"; problems=1; }
done
(( problems )) || printf -- '- No compile failures, no checksum disagreements, no exit-status surprises.\n'
for name in "${NAMES[@]}"; do
    [[ -n "${NOTE[$name]}" ]] && printf -- '- `%s`: %s\n' "$name" "${NOTE[$name]}"
    # An all-zero checksum usually means the fold never accumulated
    # anything, i.e. the interesting path was never taken. The row is
    # still a valid three-way comparison, but of less work than the
    # source suggests.
    [[ "${SUM_NU[$name]}${SUM_C[$name]}${SUM_RS[$name]}" == *0000000000000000* ]] && \
        printf -- '- `%s`: the checksum is all-zero in every language — the accumulator was never fed, so the benchmark exercises only its early-out path. A real comparison, of less work than the source implies.\n' "$name"
done
printf -- '- All three back ends are LLVM-based and all three are allowed to be clever:\n'
printf -- '  LLVM composes the affine LCG recurrence, folding several iterations into\n'
printf -- '  one multiply-add, so a run-time cell measures *optimised* throughput and\n'
printf -- '  not the source-level iteration count. Different unroll factors between\n'
printf -- '  the languages are a real part of what is being measured — identical\n'
printf -- '  algorithm, each compiler on its own `-O2` settings.\n'
printf -- '- Timings are wall clock on a machine that was not otherwise quiesced:\n'
printf -- '  expect a few per cent of run-to-run drift, and more on a machine with an\n'
printf -- '  active thermal or frequency governor.\n'
printf -- '- A cell under ~10 ms is mostly process start-up, dynamic linking and page\n'
printf -- '  faults rather than the kernel under test. Those ratios move noticeably\n'
printf -- '  between invocations of this script; do not read them as a language\n'
printf -- '  difference. The rows worth comparing are the ones in the tens of\n'
printf -- '  milliseconds and up.\n'
} >> "$OUT"

echo "run phase done     → $OUT" >&2
echo "$OUT"
