#!/usr/bin/env bash
# bench/run_micro.sh — compile-time + run-time comparison for the u64
# micro-benchmark set (the `benchmark-contract:` files) across NURL, C
# and Rust, at every optimisation level in $LEVELS (default: -O2 and
# -O0).
#
# Three phases, in this order:
#   1. compile every source in every available language at every level,
#      timing each compiler invocation, then write the compile-time
#      tables;
#   2. run the correctness gate: every language is also built in
#      "verify" mode, which dumps the 8 little-endian checksum bytes to
#      stdout, and all of those dumps — across languages *and* across
#      optimisation levels — must be byte-identical. A benchmark whose
#      builds disagree is still timed, but the report marks it: a speed
#      number for a program computing the wrong thing is worthless;
#   3. run every binary, timing each, then append the run-time tables
#      and the -O0-vs-baseline comparison.
#
# Everything lands in the same Markdown report:
#   bench/bench_results_YYYYMMDDHHMM.md
#
# Usage:
#   ./bench/run_micro.sh                       # defaults below
#   ./bench/run_micro.sh --reps 9              # 9 timed runs per cell
#   ./bench/run_micro.sh --compile-reps 5      # 5 timed compiles per cell
#   ./bench/run_micro.sh --bench hash_join     # one benchmark only
#   ./bench/run_micro.sh --levels "O2 O0"      # which levels to sweep
#   ./bench/run_micro.sh --levels O2           # baseline only, as before
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
LEVELS=(O2 O0)

while (( $# > 0 )); do
    case "$1" in
        --reps)         RUN_REPS="$2"; shift 2 ;;
        --compile-reps) COMPILE_REPS="$2"; shift 2 ;;
        --timeout)      RUN_TIMEOUT="$2"; shift 2 ;;
        --bench)        BENCH_FILTER="$2"; shift 2 ;;
        --levels)       read -r -a LEVELS <<< "$2"; shift 2 ;;
        --out)          OUT="$2"; shift 2 ;;
        -h|--help)      sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)              echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

(( ${#LEVELS[@]} == 0 )) && { echo "--levels needs at least one level" >&2; exit 2; }

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

# ── optimisation levels ──────────────────────────────────────────
# set_flags <level> fills the three flag arrays for that level.
#
# NURL's `-flto` is not a tuning choice: stdlib/runtime.o *is* LLVM
# bitcode and will not link without it. It does not smuggle optimisation
# into the -O0 row — clang forwards `-plugin-opt=O0` to the LTO code
# generator, so the level reaches codegen rather than stopping at the
# (always unoptimised) IR that nurlc emits. Note also that nurlc itself
# has no optimisation switch, so its front-end column is the same work at
# every level and the two rows should differ only by noise.
#
# Rust's release flag `-O` is exactly `-C opt-level=2`; both levels are
# spelled the long way so the report's command column lines up.
#
# Why the two NURL stages are driven directly instead of through
# `nurl.sh`: the driver runs the same `nurlc` and the same `clang` line
# and produces a byte-identical binary, but it first probes the
# environment — link probes against -lsqlite3, -lzstd and friends to
# decide which optional libraries exist. That is ~200 ms of fixed cost
# per invocation, the same for every input, and it is environment
# detection rather than compilation of the program. Charging it to
# NURL's compile column against a bare `clang x.c` (which has no
# analogue) would measure the wrong thing. Anyone reproducing a single
# binary by hand with `nurl.sh` gets the same output, just ~200 ms later.
set_flags() {
    case "$1" in
        O2) NURL_LL_FLAGS=(-O2 -flto -Wl,--as-needed)
            C_FLAGS=(-O2)
            RS_FLAGS=(-C opt-level=2) ;;
        O0) NURL_LL_FLAGS=(-O0 -flto -Wl,--as-needed)
            C_FLAGS=(-O0)
            RS_FLAGS=(-C opt-level=0) ;;
        *)  echo "unknown optimisation level: $1 (known: O2, O0)" >&2; exit 2 ;;
    esac
}

# Validate the requested levels before spending minutes on phase 1.
for lvl in "${LEVELS[@]}"; do set_flags "$lvl"; done

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
    [[ -z "$1" || -z "$2" ]] && { echo "—"; return; }
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
# Every table below is keyed "<level>|<benchmark>".
declare -A NU_FRONT NU_BACK NU_TOTAL C_US RS_US
declare -A NU_BIN C_BIN RS_BIN
declare -A NU_VBIN C_VBIN RS_VBIN
declare -A ERR
declare -A NOTE
NAMES=()

for entry in "${ROSTER[@]}"; do
    IFS='|' read -r name nu c rs note <<< "$entry"
    [[ -n "$BENCH_FILTER" && "$name" != "$BENCH_FILTER" ]] && continue
    NAMES+=("$name")
    NOTE[$name]="$note"
done
(( ${#NAMES[@]} == 0 )) && { echo "no benchmark matched --bench $BENCH_FILTER" >&2; exit 2; }

for lvl in "${LEVELS[@]}"; do
    set_flags "$lvl"
    LB="$BUILD/$lvl"
    mkdir -p "$LB"

    for entry in "${ROSTER[@]}"; do
        IFS='|' read -r name nu c rs note <<< "$entry"
        [[ -n "$BENCH_FILTER" && "$name" != "$BENCH_FILTER" ]] && continue
        key="$lvl|$name"

        NU_FRONT[$key]=n/a; NU_BACK[$key]=n/a; NU_TOTAL[$key]=n/a
        C_US[$key]=n/a;     RS_US[$key]=n/a
        NU_BIN[$key]="";    C_BIN[$key]="";    RS_BIN[$key]=""
        NU_VBIN[$key]="";   C_VBIN[$key]="";   RS_VBIN[$key]=""
        ERR[$key]=""

        # ── NURL: nurlc (.nu → .ll) then clang (.ll + runtime → binary).
        # nurlc resolves `$`-imports relative to its CWD, so it runs from
        # $ROOT even though these files import nothing.
        if (( have_nurl )) && [[ -n "$nu" && -f "$BENCH/$nu" ]]; then
            local_front=(); local_back=()
            for ((r=0; r<COMPILE_REPS; r++)); do
                printf '  …%-18s -%s compile nurl %d/%d\r' "$name" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
                rm -f "$LB/$name.ll" "$LB/${name}_nu"
                t0=$(now_us)
                ( cd "$ROOT" && "$NURLC" "$BENCH/$nu" > "$LB/$name.ll" 2> "$LB/$name.nurlc.err" )
                ec=$?
                t1=$(now_us)
                if (( ec != 0 )); then
                    local_front=(FAIL); local_back=(FAIL)
                    ERR[$key]="nurlc: $(head -1 "$LB/$name.nurlc.err")"
                    break
                fi
                local_front+=( $(( t1 - t0 )) )
                t0=$(now_us)
                "$CLANG" "${NURL_LL_FLAGS[@]}" "$LB/$name.ll" "$RUNTIME" \
                         -lm -lpthread -o "$LB/${name}_nu" \
                         > "$LB/$name.clang.err" 2>&1
                ec=$?
                t1=$(now_us)
                if (( ec != 0 )); then
                    local_back=(FAIL)
                    ERR[$key]="clang: $(grep -m1 -i error "$LB/$name.clang.err")"
                    break
                fi
                local_back+=( $(( t1 - t0 )) )
            done
            f=$(median_us "${local_front[@]}")
            b=$(median_us "${local_back[@]}")
            NU_FRONT[$key]=$f; NU_BACK[$key]=$b
            if [[ "$f" == FAIL || "$b" == FAIL ]]; then
                NU_TOTAL[$key]=FAIL
            else
                NU_TOTAL[$key]=$(( f + b ))
                NU_BIN[$key]="$LB/${name}_nu"
            fi
        fi

        # ── C: one clang invocation.
        if (( have_c )) && [[ -n "$c" && -f "$BENCH/$c" ]]; then
            samples=()
            for ((r=0; r<COMPILE_REPS; r++)); do
                printf '  …%-18s -%s compile c    %d/%d\r' "$name" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
                rm -f "$LB/${name}_c"
                time_cmd one "$CLANG" "${C_FLAGS[@]}" "$BENCH/$c" -o "$LB/${name}_c"
                [[ "$one" == FAIL ]] && { ERR[$key]="cc: $(grep -m1 -i error "$LOG")"; samples=(FAIL); break; }
                samples+=("$one")
            done
            C_US[$key]=$(median_us "${samples[@]}")
            [[ "${C_US[$key]}" != FAIL ]] && C_BIN[$key]="$LB/${name}_c"
        fi

        # ── Rust: one rustc invocation.
        if (( have_rs )) && [[ -n "$rs" && -f "$BENCH/$rs" ]]; then
            samples=()
            for ((r=0; r<COMPILE_REPS; r++)); do
                printf '  …%-18s -%s compile rust %d/%d\r' "$name" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
                rm -f "$LB/${name}_rs"
                time_cmd one "$RUSTC" "${RS_FLAGS[@]}" "$BENCH/$rs" -o "$LB/${name}_rs"
                [[ "$one" == FAIL ]] && { ERR[$key]="rustc: $(grep -m1 -E '^error' "$LOG")"; samples=(FAIL); break; }
                samples+=("$one")
            done
            RS_US[$key]=$(median_us "${samples[@]}")
            [[ "${RS_US[$key]}" != FAIL ]] && RS_BIN[$key]="$LB/${name}_rs"
        fi

        # ── verify-mode builds (untimed; the correctness gate only).
        # NURL needs no second build: its checksum dump is behind a
        # `--verify` argument rather than a compile-time switch.
        [[ -n "${NU_BIN[$key]}" ]] && NU_VBIN[$key]="${NU_BIN[$key]}"
        if [[ -n "${C_BIN[$key]}" ]]; then
            "$CLANG" "${C_FLAGS[@]}" -DBENCH_VERIFY "$BENCH/$c" -o "$LB/${name}_c_v" 2>/dev/null \
                && C_VBIN[$key]="$LB/${name}_c_v"
        fi
        if [[ -n "${RS_BIN[$key]}" ]]; then
            "$RUSTC" "${RS_FLAGS[@]}" --cfg bench_verify "$BENCH/$rs" -o "$LB/${name}_rs_v" 2>/dev/null \
                && RS_VBIN[$key]="$LB/${name}_rs_v"
        fi
    done
done
printf '                                                          \r' >&2

# ── fixed-cost floor ─────────────────────────────────────────────
# What each toolchain costs for a program that does nothing. NURL's
# floor is dominated by the LTO link against stdlib/runtime.o, which
# every NURL binary pays whether or not it calls into the runtime;
# subtracting the floor from a cell gives its marginal compile cost.
declare -A FL_NU_F FL_NU_B FL_NU_T FL_C FL_RS
printf '@ main → i {\n    ^ 0\n}\n'      > "$BUILD/_floor.nu"
printf 'int main(void) { return 0; }\n'  > "$BUILD/_floor.c"
printf 'fn main() {}\n'                  > "$BUILD/_floor.rs"

for lvl in "${LEVELS[@]}"; do
    set_flags "$lvl"
    LB="$BUILD/$lvl"
    FL_NU_F[$lvl]=n/a; FL_NU_B[$lvl]=n/a; FL_NU_T[$lvl]=n/a
    FL_C[$lvl]=n/a;    FL_RS[$lvl]=n/a

    if (( have_nurl )); then
        f_samples=(); b_samples=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s -%s compile nurl %d/%d\r' "(floor)" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
            rm -f "$LB/_floor.ll" "$LB/_floor_nu"
            t0=$(now_us)
            ( cd "$ROOT" && "$NURLC" "$BUILD/_floor.nu" > "$LB/_floor.ll" 2>/dev/null )
            t1=$(now_us)
            f_samples+=( $(( t1 - t0 )) )
            t0=$(now_us)
            "$CLANG" "${NURL_LL_FLAGS[@]}" "$LB/_floor.ll" "$RUNTIME" \
                     -lm -lpthread -o "$LB/_floor_nu" > /dev/null 2>&1
            t1=$(now_us)
            b_samples+=( $(( t1 - t0 )) )
        done
        FL_NU_F[$lvl]=$(median_us "${f_samples[@]}")
        FL_NU_B[$lvl]=$(median_us "${b_samples[@]}")
        FL_NU_T[$lvl]=$(( FL_NU_F[$lvl] + FL_NU_B[$lvl] ))
    fi
    if (( have_c )); then
        samples=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s -%s compile c    %d/%d\r' "(floor)" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
            time_cmd one "$CLANG" "${C_FLAGS[@]}" "$BUILD/_floor.c" -o "$LB/_floor_c"
            samples+=("$one")
        done
        FL_C[$lvl]=$(median_us "${samples[@]}")
    fi
    if (( have_rs )); then
        samples=()
        for ((r=0; r<COMPILE_REPS; r++)); do
            printf '  …%-18s -%s compile rust %d/%d\r' "(floor)" "$lvl" "$((r+1))" "$COMPILE_REPS" >&2
            time_cmd one "$RUSTC" "${RS_FLAGS[@]}" "$BUILD/_floor.rs" -o "$LB/_floor_rs"
            samples+=("$one")
        done
        FL_RS[$lvl]=$(median_us "${samples[@]}")
    fi
done
printf '                                                          \r' >&2

# ── report header ────────────────────────────────────────────────
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

printf 'Every benchmark is built at each of these levels, and each level gets its\n'
printf 'own compile-time and run-time table.\n\n'
printf '| Level | NURL | C | Rust |\n|---|---|---|---|\n'
for lvl in "${LEVELS[@]}"; do
    set_flags "$lvl"
    printf '| `-%s` | `nurlc x.nu > x.ll` + `clang %s x.ll stdlib/runtime.o -lm -lpthread` | `clang %s x.c` | `rustc %s x.rs` |\n' \
        "$lvl" "${NURL_LL_FLAGS[*]}" "${C_FLAGS[*]}" "${RS_FLAGS[*]}"
done
printf '\n'
printf 'NURL always links with `-flto` because `stdlib/runtime.o` *is* LLVM\n'
printf 'bitcode and will not link otherwise; that does not smuggle optimisation\n'
printf 'into the `-O0` row, since clang forwards `-plugin-opt=O0` to the LTO code\n'
printf 'generator. `nurlc` has no optimisation switch of its own — it always emits\n'
printf 'unoptimised IR — so its front-end column is the same work at every level\n'
printf 'and the rows differ only by noise. Rust `-O` is `-C opt-level=2`; the long\n'
printf 'spelling is used so the two levels read symmetrically.\n\n'

printf '| Setting | Value |\n|---|---|\n'
lvl_list=$(printf -- '`-%s`, ' "${LEVELS[@]}")
printf '| Optimisation levels | %s |\n' "${lvl_list%, }"
printf '| Timed compiles per cell | %d (median) |\n' "$COMPILE_REPS"
printf '| Timed runs per cell | %d (median) |\n' "$RUN_REPS"
printf '| Per-run timeout | %d s |\n' "$RUN_TIMEOUT"
printf '\n'

printf '## 1. Compile time (median, ms)\n\n'
printf 'NURL is split into its two stages: `nurlc` emits LLVM IR, then `clang`\n'
printf 'lowers that IR and links it against the runtime. `NURL total` is the\n'
printf 'number comparable to the C and Rust columns — those are single\n'
printf 'invocations that also do codegen and linking.\n\n'
printf 'The first row of each table is the floor: what each toolchain costs for a\n'
printf 'program that does nothing. For NURL that floor is dominated by the LTO\n'
printf 'link against `stdlib/runtime.o` — a fixed cost every NURL binary pays.\n'
printf 'Subtract the floor from a cell to see the marginal compile cost of that\n'
printf 'benchmark.\n'
} > "$OUT"

# The totals row sums only the benchmarks that exist in all three
# languages, so the three columns stay comparable to each other.
declare -A CSUM_NU CSUM_C CSUM_RS
for lvl in "${LEVELS[@]}"; do
    {
    printf '\n### `-%s`\n\n' "$lvl"
    printf '| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |\n'
    printf '|---|---:|---:|---:|---:|---:|\n'
    printf '| _(floor: empty program)_ | _%s_ | _%s_ | _**%s**_ | _%s_ | _%s_ |\n' \
        "$(ms "${FL_NU_F[$lvl]}")" "$(ms "${FL_NU_B[$lvl]}")" "$(ms "${FL_NU_T[$lvl]}")" \
        "$(ms "${FL_C[$lvl]}")" "$(ms "${FL_RS[$lvl]}")"
    } >> "$OUT"

    sum_nu=0; sum_c=0; sum_rs=0; n_common=0
    for name in "${NAMES[@]}"; do
        key="$lvl|$name"
        printf '| `%s` | %s | %s | **%s** | %s | %s |\n' \
            "$name" "$(ms "${NU_FRONT[$key]}")" "$(ms "${NU_BACK[$key]}")" \
            "$(ms "${NU_TOTAL[$key]}")" "$(ms "${C_US[$key]}")" "$(ms "${RS_US[$key]}")"
        vn=${NU_TOTAL[$key]}; vc=${C_US[$key]}; vr=${RS_US[$key]}
        if [[ "$vn" =~ ^[0-9]+$ && "$vc" =~ ^[0-9]+$ && "$vr" =~ ^[0-9]+$ ]]; then
            sum_nu=$(( sum_nu + vn )); sum_c=$(( sum_c + vc )); sum_rs=$(( sum_rs + vr ))
            n_common=$(( n_common + 1 ))
        fi
    done >> "$OUT"
    CSUM_NU[$lvl]=$sum_nu; CSUM_C[$lvl]=$sum_c; CSUM_RS[$lvl]=$sum_rs
    printf '| **sum over the %d rows built by all three** | | | **%s** | %s | %s |\n' \
        "$n_common" "$(ms "$sum_nu")" "$(ms "$sum_c")" "$(ms "$sum_rs")" >> "$OUT"
done
printf '\n`n/a` = no source file in that language. `FAIL` = the compiler rejected it (see Notes).\n' >> "$OUT"

echo "compile phase done → $OUT" >&2

# ── phase 2: correctness gate ────────────────────────────────────
# Keyed "<level>|<benchmark>" as well: a checksum that changes with the
# optimisation level is a miscompile, and this is the cheapest place to
# catch one.
declare -A SUM_NU SUM_C SUM_RS
declare -A VERDICT EXPECT_EC REF
for name in "${NAMES[@]}"; do
    printf '  …%-18s verify\r' "$name" >&2
    present=()
    for lvl in "${LEVELS[@]}"; do
        key="$lvl|$name"
        SUM_NU[$key]=""; SUM_C[$key]=""; SUM_RS[$key]=""
        [[ -n "${NU_VBIN[$key]}" ]] && SUM_NU[$key]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${NU_VBIN[$key]}" --verify | xxd -p)
        [[ -n "${C_VBIN[$key]}"  ]] && SUM_C[$key]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${C_VBIN[$key]}" | xxd -p)
        [[ -n "${RS_VBIN[$key]}" ]] && SUM_RS[$key]=$(timeout -s KILL "${RUN_TIMEOUT}s" "${RS_VBIN[$key]}" | xxd -p)
        for s in "${SUM_NU[$key]}" "${SUM_C[$key]}" "${SUM_RS[$key]}"; do
            [[ -n "$s" ]] && present+=("$s")
        done
    done

    if (( ${#present[@]} == 0 )); then
        VERDICT[$name]="no build"
        EXPECT_EC[$name]=""
        REF[$name]=""
    else
        REF[$name]="${present[0]}"
        agree=1
        for s in "${present[@]}"; do [[ "$s" != "${present[0]}" ]] && agree=0; done
        if (( ${#present[@]} == 1 )); then VERDICT[$name]="single build"
        elif (( agree )); then VERDICT[$name]="identical"
        else VERDICT[$name]="**MISMATCH**"
        fi
        # The exit status every build must report: checksum & 0x7f,
        # i.e. the low byte of the little-endian dump masked to 7 bits.
        EXPECT_EC[$name]=$(( 0x${present[0]:0:2} & 0x7f ))
    fi
done
printf '                                                          \r' >&2

# mark <dump> <reference> → ✓ / ✗ / n/a
mark() { [[ -z "$1" ]] && echo "n/a" || { [[ "$1" == "$2" ]] && echo "✓" || echo "✗"; }; }

{
printf '\n## 2. Correctness gate\n\n'
printf 'Every build writes the same 8 little-endian checksum bytes when built in\n'
printf 'verify mode (`-DBENCH_VERIFY` for C, `--cfg bench_verify` for Rust,\n'
printf '`--verify` on the command line for NURL). The gate spans both axes: all\n'
printf 'three languages *and* every optimisation level must produce the same\n'
printf 'bytes, so a checksum that moves when the optimiser is switched on is\n'
printf 'caught here. A timing number below is only meaningful for a row that says\n'
printf '`identical`.\n\n'
printf '| Benchmark | Checksum (LE hex) |'
for lvl in "${LEVELS[@]}"; do printf ' NURL `-%s` | C `-%s` | Rust `-%s` |' "$lvl" "$lvl" "$lvl"; done
printf ' Verdict |\n'
printf '|---|---|'
for lvl in "${LEVELS[@]}"; do printf ':-:|:-:|:-:|'; done
printf -- '---|\n'
for name in "${NAMES[@]}"; do
    printf '| `%s` | `%s` |' "$name" "${REF[$name]:---}"
    for lvl in "${LEVELS[@]}"; do
        key="$lvl|$name"
        printf ' %s | %s | %s |' \
            "$(mark "${SUM_NU[$key]}" "${REF[$name]}")" \
            "$(mark "${SUM_C[$key]}"  "${REF[$name]}")" \
            "$(mark "${SUM_RS[$key]}" "${REF[$name]}")"
    done
    printf ' %s |\n' "${VERDICT[$name]}"
done
} >> "$OUT"

# ── phase 3: run ─────────────────────────────────────────────────
declare -A RUN_NU RUN_C RUN_RS
declare -A EC_NOTE
for lvl in "${LEVELS[@]}"; do
    for name in "${NAMES[@]}"; do
        key="$lvl|$name"
        RUN_NU[$key]=n/a; RUN_C[$key]=n/a; RUN_RS[$key]=n/a; EC_NOTE[$key]=""
        for lang in nu c rs; do
            case $lang in
                nu) bin="${NU_BIN[$key]}" ;;
                c)  bin="${C_BIN[$key]}"  ;;
                rs) bin="${RS_BIN[$key]}" ;;
            esac
            [[ -z "$bin" ]] && continue
            samples=()
            for ((r=0; r<RUN_REPS; r++)); do
                printf '  …%-18s -%s run %-4s %d/%d\r' "$name" "$lvl" "$lang" "$((r+1))" "$RUN_REPS" >&2
                time_run one ec "$bin"
                samples+=("$one")
                # The exit status carries checksum & 0x7f — cross-check it
                # against the verify dump, so a run-phase regression cannot
                # hide behind a passing gate.
                if [[ "$one" != TIMEOUT && "$one" != FAIL && -n "${EXPECT_EC[$name]}" ]]; then
                    (( ec != EXPECT_EC[$name] )) && \
                        EC_NOTE[$key]="${EC_NOTE[$key]}${lang} exit=$ec (expected ${EXPECT_EC[$name]}); "
                fi
            done
            med=$(median_us "${samples[@]}")
            case $lang in
                nu) RUN_NU[$key]=$med ;;
                c)  RUN_C[$key]=$med ;;
                rs) RUN_RS[$key]=$med ;;
            esac
        done
    done
done
printf '                                                          \r' >&2

{
printf '\n## 3. Run time (median, ms)\n\n'
printf 'Wall clock of the whole process, including start-up. These binaries\n'
printf 'print nothing and return `checksum & 0x7f` as their exit status, so no\n'
printf 'I/O is being measured. The last two columns are NURL relative to the\n'
printf 'peer — below `1.00×` NURL is faster.\n'
} >> "$OUT"

declare -A RSUM_NU RSUM_C RSUM_RS
for lvl in "${LEVELS[@]}"; do
    {
    printf '\n### `-%s`\n\n' "$lvl"
    printf '| Benchmark | NURL | C | Rust | NURL / C | NURL / Rust |\n'
    printf '|---|---:|---:|---:|---:|---:|\n'
    } >> "$OUT"

    r_nu=0; r_c=0; r_rs=0; r_common=0
    for name in "${NAMES[@]}"; do
        key="$lvl|$name"
        printf '| `%s` | %s | %s | %s | %s | %s |\n' "$name" \
            "$(ms "${RUN_NU[$key]}")" "$(ms "${RUN_C[$key]}")" "$(ms "${RUN_RS[$key]}")" \
            "$(ratio "${RUN_NU[$key]}" "${RUN_C[$key]}")" \
            "$(ratio "${RUN_NU[$key]}" "${RUN_RS[$key]}")"
        vn=${RUN_NU[$key]}; vc=${RUN_C[$key]}; vr=${RUN_RS[$key]}
        if [[ "$vn" =~ ^[0-9]+$ && "$vc" =~ ^[0-9]+$ && "$vr" =~ ^[0-9]+$ ]]; then
            r_nu=$(( r_nu + vn )); r_c=$(( r_c + vc )); r_rs=$(( r_rs + vr ))
            r_common=$(( r_common + 1 ))
        fi
    done >> "$OUT"
    RSUM_NU[$lvl]=$r_nu; RSUM_C[$lvl]=$r_c; RSUM_RS[$lvl]=$r_rs
    printf '| **sum over the %d rows run in all three** | %s | %s | %s | %s | %s |\n' \
        "$r_common" "$(ms "$r_nu")" "$(ms "$r_c")" "$(ms "$r_rs")" \
        "$(ratio "$r_nu" "$r_c")" "$(ratio "$r_nu" "$r_rs")" >> "$OUT"
done

# ── what the optimiser is worth ──────────────────────────────────
# Only meaningful with more than one level; the baseline is the first
# level on the command line.
if (( ${#LEVELS[@]} > 1 )); then
    base=${LEVELS[0]}
    {
    printf '\n## 4. What the optimiser is worth\n\n'
    printf 'Each cell is that level divided by the `-%s` baseline, per language.\n' "$base"
    printf 'For run time, above `1.00×` means the unoptimised binary is that much\n'
    printf 'slower; for compile time, below `1.00×` means the compiler got that much\n'
    printf 'cheaper. Read this as "how much of the speed comes from the optimiser\n'
    printf 'rather than from the source", and note that a row whose baseline is only\n'
    printf 'a few milliseconds is mostly process start-up and cannot show a large\n'
    printf 'ratio however slow its kernel becomes.\n'
    } >> "$OUT"

    for lvl in "${LEVELS[@]:1}"; do
        {
        printf '\n### `-%s` vs `-%s`\n\n' "$lvl" "$base"
        printf '| Benchmark | run NURL | run C | run Rust | compile NURL | compile C | compile Rust |\n'
        printf '|---|---:|---:|---:|---:|---:|---:|\n'
        for name in "${NAMES[@]}"; do
            k="$lvl|$name"; b="$base|$name"
            printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' "$name" \
                "$(ratio "${RUN_NU[$k]}" "${RUN_NU[$b]}")" \
                "$(ratio "${RUN_C[$k]}"  "${RUN_C[$b]}")" \
                "$(ratio "${RUN_RS[$k]}" "${RUN_RS[$b]}")" \
                "$(ratio "${NU_TOTAL[$k]}" "${NU_TOTAL[$b]}")" \
                "$(ratio "${C_US[$k]}"     "${C_US[$b]}")" \
                "$(ratio "${RS_US[$k]}"    "${RS_US[$b]}")"
        done
        printf '| **sum over the common rows** | %s | %s | %s | %s | %s | %s |\n' \
            "$(ratio "${RSUM_NU[$lvl]}" "${RSUM_NU[$base]}")" \
            "$(ratio "${RSUM_C[$lvl]}"  "${RSUM_C[$base]}")" \
            "$(ratio "${RSUM_RS[$lvl]}" "${RSUM_RS[$base]}")" \
            "$(ratio "${CSUM_NU[$lvl]}" "${CSUM_NU[$base]}")" \
            "$(ratio "${CSUM_C[$lvl]}"  "${CSUM_C[$base]}")" \
            "$(ratio "${CSUM_RS[$lvl]}" "${CSUM_RS[$base]}")"
        } >> "$OUT"
    done
fi

# ── notes ────────────────────────────────────────────────────────
{
printf '\n## 5. Notes\n\n'
problems=0
for name in "${NAMES[@]}"; do
    for lvl in "${LEVELS[@]}"; do
        key="$lvl|$name"
        [[ -n "${ERR[$key]}" ]] && { printf -- '- `%s` at `-%s`: %s\n' "$name" "$lvl" "${ERR[$key]}"; problems=1; }
        [[ -n "${EC_NOTE[$key]}" ]] && { printf -- '- `%s` at `-%s`: exit-status cross-check failed — %s\n' "$name" "$lvl" "${EC_NOTE[$key]}"; problems=1; }
    done
    [[ "${VERDICT[$name]}" == '**MISMATCH**' ]] && { printf -- '- `%s`: the builds disagree on the checksum — treat its timings as void.\n' "$name"; problems=1; }
done
(( problems )) || printf -- '- No compile failures, no checksum disagreements, no exit-status surprises.\n'
for name in "${NAMES[@]}"; do
    [[ -n "${NOTE[$name]}" ]] && printf -- '- `%s`: %s\n' "$name" "${NOTE[$name]}"
    # An all-zero checksum usually means the fold never accumulated
    # anything, i.e. the interesting path was never taken. The row is
    # still a valid three-way comparison, but of less work than the
    # source suggests.
    [[ "${REF[$name]}" == 0000000000000000 ]] && \
        printf -- '- `%s`: the checksum is all-zero in every build — the accumulator was never fed, so the benchmark exercises only its early-out path. A real comparison, of less work than the source implies.\n' "$name"
done
printf -- '- All three back ends are LLVM-based and all three are allowed to be clever\n'
printf -- '  at `-O2`: LLVM composes the affine LCG recurrence, folding several\n'
printf -- '  iterations into one multiply-add, so an `-O2` run-time cell measures\n'
printf -- '  *optimised* throughput and not the source-level iteration count.\n'
printf -- '  Different unroll factors between the languages are a real part of what\n'
printf -- '  is being measured — identical algorithm, each compiler on its own\n'
printf -- '  settings. The `-O0` tables are the other end of that: no unrolling, no\n'
printf -- '  recurrence folding, everything through memory, so they compare the code\n'
printf -- '  each front end emits far more directly than the `-O2` tables do.\n'
printf -- '- `-O0` is not a build anyone should ship, and it is not a fair proxy for\n'
printf -- '  "language speed" either. It is here because it separates two things the\n'
printf -- '  `-O2` tables conflate: what a front end emits, and what LLVM can then\n'
printf -- '  recover. A benchmark where NURL trails at `-O0` but ties at `-O2` is\n'
printf -- '  one where the optimiser is doing the work.\n'
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
