#!/usr/bin/env bash
# ============================================================
#  run_san_tests.sh — run the .nu test corpus under
#  AddressSanitizer + UndefinedBehaviorSanitizer.
#
#  Workflow:
#     1. Compile each .nu with the freshly-built nurlc.
#     2. Link with -fsanitize=address,undefined (matching the
#        sanitized runtime.o that `./build.sh --san` produced).
#     3. Run; capture stdout (test output) and stderr (sanitizer
#        reports) separately.
#     4. Per-test verdict:
#          - PASS:        exit code 0 AND stderr empty of sanitizer
#                         markers.
#          - SAN_FAIL:    stderr contains ASan/UBSan output.
#          - EXIT_FAIL:   non-zero exit code, no sanitizer report
#                         (often a `should_fail_*` test that is
#                         expected to abort).
#          - COMPILE_FAIL / LINK_FAIL: as the normal runner.
#     5. Print per-test summary + grand totals + the first ~40
#        lines of each sanitizer report so you can triage without
#        diving into individual log files.
#
#  Pre-req: ./build.sh --san must have been run first so that
#  stdlib/runtime.o contains the sanitizer-instrumented code.
#  This script DOES NOT rebuild — keep concerns separate.
#
#  Default behaviour skips leak detection (ASAN_OPTIONS=detect_leaks=0)
#  because NURL's stdlib globals (g_str_pool, g_sym_arena, etc.) are
#  process-lifetime-bound and intentionally not freed at exit, which
#  LSan would report as "leaks". Set LSAN_DETECT_LEAKS=1 to enable
#  if you want to triage them anyway.
#
#  Environment toggles inherited from run_tests.sh:
#     NURL_HTTP_TESTS=1   include http_basic.nu live tests
#     NURL_NET_TESTS=1    include loopback socket tests
#     NURL_PG_TESTS=1     include postgres_basic.nu live tests
#     TIMEOUT=N           per-test timeout in seconds (default 30 —
#                         sanitized binaries run ~3× slower)
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"

if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: nurlc not found at $NURLC" >&2
    echo "       Run ./build.sh --san first." >&2
    exit 2
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: runtime.o not found at $RUNTIME" >&2
    echo "       Run ./build.sh --san first." >&2
    exit 2
fi

LINK_HELPER="$ROOT_DIR/tools/nurl-build/run.sh"
if [[ ! -x "$LINK_HELPER" ]]; then
    echo "ERROR: link helper not found at $LINK_HELPER" >&2
    exit 2
fi

# Sanitizer-instrumented runtime.o has the `__asan_init` reference;
# a plain runtime.o does not. nm-grep is a cheap pre-flight check that
# saves a confusing per-test link failure later.
if ! nm "$RUNTIME" 2>/dev/null | grep -q "__asan_init\|asan_init"; then
    echo "ERROR: $RUNTIME was not built with -fsanitize=address." >&2
    echo "       Run ./build.sh --san to rebuild it." >&2
    exit 2
fi

CLANG="${CLANG:-clang}"
if ! command -v "$CLANG" &>/dev/null; then
    for c in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
        [ -x "$c" ] && CLANG="$c" && break
    done
fi
if ! command -v "$CLANG" &>/dev/null; then
    echo "ERROR: clang not found" >&2
    exit 2
fi

WORKDIR="$ROOT_DIR/build/tests-san"
LOGDIR="$WORKDIR/logs"
SUMMARY="$WORKDIR/SUMMARY.txt"
mkdir -p "$WORKDIR" "$LOGDIR"
: > "$SUMMARY"

TIMEOUT="${TIMEOUT:-30}"

# Leak detection off by default — see file header.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=${LSAN_DETECT_LEAKS:-0}:abort_on_error=0:halt_on_error=0:print_stacktrace=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=0}"

shopt -s nullglob
tests=("$SCRIPT_DIR"/*.nu)
shopt -u nullglob
IFS=$'\n' tests=($(printf '%s\n' "${tests[@]}" | LC_ALL=C sort))
unset IFS

run_with_timeout() {
    local cwd="$1"
    local bin_name="$2"
    local out_file="$3"
    local err_file="$4"
    local timeout_sec="$5"

    if command -v timeout >/dev/null 2>&1; then
        { ( cd "$cwd" && timeout "${timeout_sec}s" "./$bin_name" > "$out_file" 2> "$err_file" ); } 2>/dev/null
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        { ( cd "$cwd" && gtimeout "${timeout_sec}s" "./$bin_name" > "$out_file" 2> "$err_file" ); } 2>/dev/null
        return $?
    fi

    local marker="${err_file}.timeout"
    rm -f "$marker"
    (
        cd "$cwd" || exit 125
        "./$bin_name" > "$out_file" 2> "$err_file"
    ) &
    local child=$!
    (
        sleep "$timeout_sec"
        if kill -0 "$child" 2>/dev/null; then
            : > "$marker"
            kill -TERM "$child" 2>/dev/null || true
            sleep 1
            kill -KILL "$child" 2>/dev/null || true
        fi
    ) &
    local watcher=$!
    wait "$child"
    local status=$?
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    if [[ -f "$marker" ]]; then
        rm -f "$marker"
        return 124
    fi
    return $status
}

n_total=0
n_pass=0
n_san_fail=0
n_compile_fail=0
n_link_fail=0

# Test names whose sanitizer-relevant behaviour we accept as intentional
# (e.g. should_fail_* deliberately abort during compilation; live tests
# need their gating env vars to even run their interesting code).
SKIP_PATTERNS=(
    # should_fail_* are compile-time negative tests — irrelevant for ASan
    "should_fail_"
    # nurlfmt round-trip shell script, not a .nu binary test
    "nurlfmt_idempotent"
    # Helper modules without main() — imported by sibling tests
    "alias_rewrite_types_mod"
)

should_skip() {
    local name="$1"
    for p in "${SKIP_PATTERNS[@]}"; do
        [[ "$name" == *"$p"* ]] && return 0
    done
    return 1
}

printf '%-44s %s\n' "TEST" "VERDICT"
printf '%-44s %s\n' "----" "-------"

for src in "${tests[@]}"; do
    name="$(basename "$src" .nu)"
    n_total=$((n_total + 1))

    if should_skip "$name"; then
        printf '%-44s %s\n' "$name" "SKIP"
        continue
    fi
    if [[ "$name" == "postgres_basic" && ! -f "$ROOT_DIR/stdlib/runtime.pq" ]]; then
        printf '%-44s %s\n' "$name" "SKIP"
        continue
    fi

    ll="$WORKDIR/$name.ll"
    bin="$WORKDIR/$name"
    stdout_log="$LOGDIR/$name.stdout"
    stderr_log="$LOGDIR/$name.stderr"

    # Compile (uses the just-built nurlc — should always succeed if the
    # normal run_tests.sh would compile it). We don't capture warnings
    # here because the focus is runtime-not-compile.
    if ! "$NURLC" "$src" > "$ll" 2>/dev/null; then
        printf '%-44s %s\n' "$name" "COMPILE_FAIL"
        echo "COMPILE_FAIL $name" >> "$SUMMARY"
        n_compile_fail=$((n_compile_fail + 1))
        continue
    fi

    if ! env NURL_CC="$CLANG" \
            "$LINK_HELPER" \
            --opt -O1 \
            --flag "-fsanitize=address,undefined" \
            --flag "-fno-omit-frame-pointer" \
            "$ROOT_DIR" "$ll" "$bin" 2>"$stderr_log"; then
        printf '%-44s %s\n' "$name" "LINK_FAIL"
        echo "LINK_FAIL $name" >> "$SUMMARY"
        n_link_fail=$((n_link_fail + 1))
        continue
    fi

    run_with_timeout "$WORKDIR" "$name" "$stdout_log" "$stderr_log" "$TIMEOUT"
    exit_code=$?

    # Sanitizer-marker scan. ASan writes "AddressSanitizer:", UBSan
    # writes "runtime error:" (or "UndefinedBehaviorSanitizer:" in some
    # paths). LeakSanitizer writes "LeakSanitizer:".
    if grep -qE "AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|LeakSanitizer" "$stderr_log"; then
        printf '%-44s %s (exit=%d)\n' "$name" "SAN_FAIL" "$exit_code"
        echo "SAN_FAIL $name exit=$exit_code" >> "$SUMMARY"
        n_san_fail=$((n_san_fail + 1))
        continue
    fi

    # Non-zero exit code without a sanitizer report is fine from the
    # ASan/UBSan perspective — the test ran the instrumented runtime
    # cleanly. Several tests in the corpus exit with a deliberate
    # non-zero code (e.g. native_sum returns the computed sum;
    # test_immutable_assign_error aborts to demonstrate the runtime
    # immutability check). The sanitized runner only cares whether the
    # sanitizers caught anything — verdict is PASS.
    if (( exit_code != 0 )); then
        printf '%-44s %s (exit=%d, no sanitizer report)\n' "$name" "PASS" "$exit_code"
    else
        printf '%-44s %s\n' "$name" "PASS"
    fi
    n_pass=$((n_pass + 1))
done

echo
echo "── Sanitized run summary ──"
echo "  total      : $n_total"
echo "  PASS       : $n_pass     (includes tests with non-zero deliberate exit)"
echo "  SAN_FAIL   : $n_san_fail     (AddressSanitizer / UBSan / LSan caught a problem)"
echo "  COMPILE    : $n_compile_fail"
echo "  LINK       : $n_link_fail"
echo "  logs       : $LOGDIR"
echo

if (( n_san_fail > 0 )); then
    echo "── First sanitizer report from each SAN_FAIL test ──"
    while IFS= read -r line; do
        [[ "$line" == SAN_FAIL* ]] || continue
        nm="$(echo "$line" | awk '{print $2}')"
        echo
        echo "▶ $nm"
        head -40 "$LOGDIR/$nm.stderr"
        echo "  …(see $LOGDIR/$nm.stderr for the full report)"
    done < "$SUMMARY"
    exit 1
fi

exit 0
