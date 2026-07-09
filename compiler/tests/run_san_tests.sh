#!/usr/bin/env bash
# ============================================================
#  run_san_tests.sh — run the .nu test corpus under
#  AddressSanitizer + UndefinedBehaviorSanitizer, IN PARALLEL.
#
#  Workflow (per test, run concurrently across NURL_SAN_JOBS workers):
#     1. Compile each .nu with the freshly-built nurlc.
#     2. Link with -fsanitize=address,undefined (matching the
#        sanitized runtime.o that `./build.sh --san` produced).
#     3. Run; capture stdout (test output) and stderr (sanitizer
#        reports) separately.
#     4. Per-test verdict:
#          - PASS:        exit code 0 (or deliberate non-zero) AND
#                         stderr empty of sanitizer markers.
#          - SAN_FAIL:    stderr contains ASan/UBSan/LSan output.
#          - COMPILE_FAIL / LINK_FAIL: as the normal runner.
#     5. Print per-test summary + grand totals + the first ~40
#        lines of each sanitizer report so you can triage without
#        diving into individual log files.
#
#  Parallelism mirrors run_tests.sh: a `run_one_san` function is
#  exported and fanned out with `xargs -P`. The per-test work touches
#  only $name-keyed files (.ll / bin / logs/$name.*), so there are no
#  shared-state races. Default worker count is nproc; override with
#  NURL_SAN_JOBS (CI may cap it to bound peak RAM from concurrent
#  sanitizer links + sanitized processes).
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
#  Environment toggles:
#     NURL_SAN_JOBS=N     worker count (default nproc)
#     LSAN_DETECT_LEAKS=1 enable leak detection
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

# Library link flags — same shape as run_tests.sh. Each is only emitted
# when build.sh dropped the corresponding sentinel.
CURL_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.curl" ]]   && CURL_LIBS="$(pkg-config --libs libcurl 2>/dev/null || echo -lcurl)"
OPENSSL_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.openssl" ]] && OPENSSL_LIBS="$(pkg-config --libs openssl 2>/dev/null || echo '-lssl -lcrypto')"
SQLITE3_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.sqlite3" ]] && SQLITE3_LIBS="$(pkg-config --libs sqlite3 2>/dev/null || echo -lsqlite3)"
PQ_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.pq" ]]      && PQ_LIBS="$(pkg-config --libs libpq 2>/dev/null || echo -lpq)"
ZLIB_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.z" ]]       && ZLIB_LIBS="$(pkg-config --libs zlib 2>/dev/null || echo -lz)"
ZSTD_LIBS=""
[[ -f "$ROOT_DIR/stdlib/runtime.zstd" ]]    && ZSTD_LIBS="$(pkg-config --libs libzstd 2>/dev/null || echo -lzstd)"
LINK_LIBS="-lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS"

WORKDIR="$ROOT_DIR/build/tests-san"
LOGDIR="$WORKDIR/logs"
mkdir -p "$WORKDIR" "$LOGDIR"

TIMEOUT="${TIMEOUT:-30}"
JOBS="${NURL_SAN_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# Leak detection off by default — see file header.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=${LSAN_DETECT_LEAKS:-0}:abort_on_error=0:halt_on_error=0:print_stacktrace=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=0}"

# should_fail_* are compile-time negative tests; nurlfmt_idempotent is a
# shell round-trip, not a binary; *_mod are helper modules without main().
SKIP_RE='(should_fail_|nurlfmt_idempotent|alias_rewrite_types_mod)'

# ── per-test worker (exported, fanned out with xargs -P) ─────────
# Echoes a single "<name> <VERDICT>" line; writes its own logs under
# $LOGDIR/$name.*  — no shared mutable state, safe to run concurrently.
run_one_san() {
    local name="$1"
    local src="$SCRIPT_DIR/$name.nu"

    if [[ "$name" =~ $SKIP_RE ]]; then echo "$name SKIP"; return; fi

    local ll="$WORKDIR/$name.ll"
    local bin="$WORKDIR/$name"
    local stdout_log="$LOGDIR/$name.stdout"
    local stderr_log="$LOGDIR/$name.stderr"

    # borrow_* — borrow-checker baseline tests with *deliberate*
    # use-after-free / double-free patterns. The normal runner compiles
    # them with --borrowck and never links/runs them; mirror that here so
    # ASan isn't asked to adjudicate code documented to be unsafe. A
    # compile that produces no diagnostic at all is the real regression.
    if [[ "$name" == borrow_* ]]; then
        if ! "$NURLC" --borrowck "$src" > "$ll" 2>"$stderr_log"; then
            echo "$name COMPILE_FAIL"; return
        fi
        echo "$name PASS"; return
    fi

    if ! "$NURLC" "$src" > "$ll" 2>/dev/null; then
        echo "$name COMPILE_FAIL"; return
    fi

    # shellcheck disable=SC2086
    if ! "$CLANG" -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
            "$ll" "$RUNTIME" $LINK_LIBS -o "$bin" 2>"$stderr_log"; then
        echo "$name LINK_FAIL"; return
    fi

    ( cd "$WORKDIR" && timeout "${TIMEOUT}s" "./$name" >"$stdout_log" 2>"$stderr_log" )

    # Sanitizer-marker scan: ASan "AddressSanitizer:", UBSan
    # "runtime error:" / "UndefinedBehaviorSanitizer:", LSan "LeakSanitizer:".
    if grep -qE "AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|LeakSanitizer" "$stderr_log"; then
        echo "$name SAN_FAIL"; return
    fi

    # A non-zero exit with no sanitizer report is fine here — several
    # tests exit non-zero deliberately; the sanitizers caught nothing.
    echo "$name PASS"
}
export -f run_one_san
export SCRIPT_DIR WORKDIR LOGDIR NURLC RUNTIME CLANG LINK_LIBS TIMEOUT SKIP_RE

# ── collect the test set ────────────────────────────────────────
shopt -s nullglob
tests=("$SCRIPT_DIR"/*.nu)
shopt -u nullglob
if [[ ${#tests[@]} -eq 0 ]]; then echo "ERROR: no .nu files in $SCRIPT_DIR" >&2; exit 2; fi
declare -a names=()
for src in "${tests[@]}"; do names+=("$(basename "$src" .nu)"); done
# Optional filter: if test names are passed as arguments, run only those.
# Used by the CI leak gate to run just the leak-pinned tests under
# LSAN_DETECT_LEAKS=1 (the whole corpus can't run leak-on — the compiler's
# process-lifetime arenas and the brevity tests leak by design). No args →
# the whole corpus, exactly as before.
if [[ $# -gt 0 ]]; then
    declare -a filtered=()
    for want in "$@"; do
        for have in "${names[@]}"; do
            [[ "$have" == "$want" ]] && filtered+=("$have")
        done
    done
    if [[ ${#filtered[@]} -eq 0 ]]; then
        echo "ERROR: none of the requested tests exist: $*" >&2; exit 2
    fi
    names=("${filtered[@]}")
fi
IFS=$'\n' names=($(printf '%s\n' "${names[@]}" | LC_ALL=C sort)); unset IFS

# ── run in parallel ─────────────────────────────────────────────
VERDICTS="$WORKDIR/.verdicts"
printf '%s\n' "${names[@]}" \
    | xargs -P "$JOBS" -I{} bash -c 'run_one_san "{}"' \
    > "$VERDICTS" 2>/dev/null

# ── report ──────────────────────────────────────────────────────
printf '%-44s %s\n' "TEST" "VERDICT"
printf '%-44s %s\n' "----" "-------"
LC_ALL=C sort "$VERDICTS" | while read -r name verdict; do
    printf '%-44s %s\n' "$name" "$verdict"
done

n_total=0; n_pass=0; n_san_fail=0; n_compile_fail=0; n_link_fail=0; n_skip=0
declare -a san_fails=()
while read -r name verdict; do
    n_total=$((n_total + 1))
    case "$verdict" in
        PASS)         n_pass=$((n_pass + 1)) ;;
        SKIP)         n_skip=$((n_skip + 1)) ;;
        SAN_FAIL)     n_san_fail=$((n_san_fail + 1)); san_fails+=("$name") ;;
        COMPILE_FAIL) n_compile_fail=$((n_compile_fail + 1)) ;;
        LINK_FAIL)    n_link_fail=$((n_link_fail + 1)) ;;
    esac
done < "$VERDICTS"

echo
echo "── Sanitized run summary ──"
echo "  total      : $n_total"
echo "  PASS       : $n_pass     (includes tests with non-zero deliberate exit)"
echo "  SKIP       : $n_skip"
echo "  SAN_FAIL   : $n_san_fail     (AddressSanitizer / UBSan / LSan caught a problem)"
echo "  COMPILE    : $n_compile_fail"
echo "  LINK       : $n_link_fail"
echo "  logs       : $LOGDIR     (jobs=$JOBS)"
echo

if (( n_san_fail > 0 )); then
    echo "── First sanitizer report from each SAN_FAIL test ──"
    for nm in "${san_fails[@]}"; do
        echo
        echo "▶ $nm"
        head -40 "$LOGDIR/$nm.stderr"
        echo "  …(see $LOGDIR/$nm.stderr for the full report)"
    done
    exit 1
fi

exit 0
