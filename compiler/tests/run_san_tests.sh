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
#          - PASS:        ran to completion AND stderr empty of
#                         sanitizer markers. A non-zero exit is fine;
#                         several tests exit non-zero deliberately and
#                         the code itself is baselined by run_tests.sh.
#          - SAN_FAIL:    stderr contains ASan/UBSan/LSan output.
#          - TIMEOUT:     the test did not finish within $TIMEOUT.
#          - COMPILE_FAIL / LINK_FAIL: as the normal runner.
#     5. Print per-test summary + grand totals + the first ~40
#        lines of each sanitizer report so you can triage without
#        diving into individual log files.
#
#  EVERY non-PASS verdict fails the run. This used to be true of
#  SAN_FAIL alone, which made the script an unreliable narrator in
#  three distinct ways, all of which read as green:
#    * a hung test writes nothing, so the sanitizer-marker scan finds
#      a clean stderr and scored it PASS — a deadlock, precisely what
#      the fiber park/unpark paths risk, was indistinguishable from
#      success;
#    * COMPILE_FAIL/LINK_FAIL were counted and printed but did not
#      affect the exit code, so a test that stopped building at all
#      was quieter than one that built and misbehaved;
#    * the borrow_* branch had its verdicts inverted — a borrow
#      violation the checker correctly rejected was labelled
#      COMPILE_FAIL, and the actual regression (checker goes silent)
#      was labelled PASS.
#  Under a sanitizer, "no output" is the shape of both perfect health
#  and total failure. Nothing may be scored on the absence of a signal
#  alone.
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
#  Which tests run here is decided by test_skips.sh, shared verbatim
#  with run_tests.sh — see that file for why it is shared.
#
#  Environment toggles:
#     NURL_SAN_JOBS=N     worker count (default nproc)
#     LSAN_DETECT_LEAKS=1 enable leak detection
#     TIMEOUT=N           per-test timeout in seconds
#     NURL_HTTP_TESTS=1 / NURL_NET_TESTS=1   (see test_skips.sh)
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTDIR="$SCRIPT_DIR/outputs"

# Tests that `$`-import a helper module spell the path repo-root-relative,
# and nurlc resolves imports against the CWD — anchor to the repo root so
# the runner works from any directory (mirrors run_tests.sh).
cd "$ROOT_DIR" || { echo "ERROR: cannot cd to $ROOT_DIR" >&2; exit 2; }

# Environment gating (network, optional native libs, platform, helper
# modules) — one definition, shared with the normal runner.
# shellcheck source=compiler/tests/test_skips.sh
. "$SCRIPT_DIR/test_skips.sh"

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

# Generous on purpose. A timeout is now a hard failure, so this bound
# has exactly one job: distinguish a genuine hang from a slow test.
# Sanitized binaries run ~3× slower and every worker is competing with
# concurrent sanitizer links, so a bound tight enough to be "useful"
# would only ever buy flaky red. A real deadlock never finishes.
TIMEOUT="${TIMEOUT:-120}"
JOBS="${NURL_SAN_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# Leak detection off by default — see file header.
#
# When it IS on, drop stack roots. LSan scans the exiting thread's stack
# for pointers, and by the time it runs main has already returned — so a
# dead frame that happens to still hold the pointer marks a real leak
# "reachable". Whether it does is a property of the machine: a 12-core
# dev box called async_chan clean and a 4-core CI runner called the same
# binary leaky, and the leak was real. Without this the gate is a coin
# flip that lands heads on the developer's machine. The whole pinned set
# passes with it, so nothing here relies on a stack root.
LSAN_ROOT_OPTS=""
[[ "${LSAN_DETECT_LEAKS:-0}" == "1" ]] && LSAN_ROOT_OPTS="use_stacks=0:"
export ASAN_OPTIONS="${ASAN_OPTIONS:-${LSAN_ROOT_OPTS}detect_leaks=${LSAN_DETECT_LEAKS:-0}:abort_on_error=0:halt_on_error=0:print_stacktrace=1}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-print_stacktrace=1:halt_on_error=0}"

# The one definition of "a sanitizer said something": ASan
# "AddressSanitizer:", UBSan "runtime error:" /
# "UndefinedBehaviorSanitizer:", LSan "LeakSanitizer:". Checked against
# every golden in outputs/ — none contains any of these strings, so a
# match cannot be a test legitimately printing one.
SAN_MARKERS='AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|LeakSanitizer'

# ── negative tests: ask the golden, not the name ────────────────
# A test whose golden's first line is "COMPILE FAIL" is one the corpus
# expects the compiler to REJECT — should_fail_*, diag_*, borrow_*, and
# whatever tomorrow's negative test is called. It never links, so there
# is no program for ASan to instrument; but the compiler itself IS
# instrumented in this build, so its diagnostic and error-recovery paths
# are exactly what we want to run under the sanitizers here (a scope
# leak in multi-error recovery is a bug this project has actually
# shipped — PR #505). So: compile it, scan the diagnostics for
# sanitizer markers, and stop there.
#
# Deriving this from the golden rather than a name prefix is the same
# "gate on what a test DOES" rule test_skips.sh applies to the network
# tests, and it was already wrong here: the old prefix list missed
# struct_lit_int_field_clash — a negative test with no distinguishing
# prefix — which spent its life reported as a spurious COMPILE_FAIL.
# It also listed nurlfmt_idempotent, which is a .sh and can never match
# the *.nu glob, and alias_rewrite_types_mod, which the shared *_mod
# rule already covers. The golden cannot drift out of sync with itself.
is_negative_test() {
    local gold="$OUTDIR/$1.txt" first
    [[ -f "$gold" ]] || return 1
    IFS= read -r first < "$gold" || return 1
    [[ "${first%$'\r'}" == "COMPILE FAIL" ]]
}

# ── per-test worker (exported, fanned out with xargs -P) ─────────
# Echoes a single "<name> <VERDICT>" line; writes its own logs under
# $LOGDIR/$name.*  — no shared mutable state, safe to run concurrently.
run_one_san() {
    local name="$1"
    local src="$SCRIPT_DIR/$name.nu"

    if [[ -n "$(is_skipped "$name")" ]]; then echo "$name SKIP"; return; fi

    local ll="$WORKDIR/$name.ll"
    local bin="$WORKDIR/$name"
    local stdout_log="$LOGDIR/$name.stdout"
    local stderr_log="$LOGDIR/$name.stderr"
    rm -f "$LOGDIR/$name.timeout"

    # ── negative tests: compile only, then judge the diagnostics ──
    # The borrow_* subset carries deliberate use-after-free / double-free
    # patterns, so ASan must not be asked to adjudicate code documented
    # to be unsafe — and it isn't, because none of these ever link. The
    # flags mirror run_tests.sh: borrow_strict_* only fire under the
    # stricter checker. WHETHER the compile failed, and with what text,
    # is baselined by run_tests.sh against the golden; the only question
    # asked here is whether the compiler stayed memory-clean saying it.
    if is_negative_test "$name"; then
        local bflag=""
        [[ "$name" == borrow_* ]]        && bflag="--borrowck"
        [[ "$name" == borrow_strict_* ]] && bflag="--strict-borrowck"
        # shellcheck disable=SC2086
        "$NURLC" $bflag "$src" > "$ll" 2>"$stderr_log"
        if grep -qE "$SAN_MARKERS" "$stderr_log"; then
            echo "$name SAN_FAIL"; return
        fi
        echo "$name PASS"; return
    fi

    # The compiler is instrumented in this build too, so its own stderr is
    # a sanitizer channel — it used to go to /dev/null, silently discarding
    # any report nurlc produced while compiling any of the ~470 positive
    # tests. Kept in its own log because the run phase overwrites
    # $stderr_log, which would have swallowed it a second time.
    local cerr="$LOGDIR/$name.compile.stderr"
    if ! "$NURLC" "$src" > "$ll" 2>"$cerr"; then
        echo "$name COMPILE_FAIL"; return
    fi
    if grep -qE "$SAN_MARKERS" "$cerr"; then
        cp -f "$cerr" "$stderr_log"; echo "$name SAN_FAIL"; return
    fi

    # shellcheck disable=SC2086
    if ! "$CLANG" -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
            "$ll" "$RUNTIME" $LINK_LIBS -o "$bin" 2>"$stderr_log"; then
        echo "$name LINK_FAIL"; return
    fi

    # Each test runs in its OWN scratch dir, as in run_tests.sh: relative-path
    # file side effects (a test writing `out.txt`, creating `pkg/`, …) would
    # otherwise collide with a sibling running concurrently — every worker
    # shared one CWD here. The binary is hard-linked in and invoked as
    # `./$name` so argv[0] stays exactly `./$name` (some tests print it).
    local rundir="$WORKDIR/run/$name"
    rm -rf "$rundir"; mkdir -p "$rundir"
    ln "$bin" "$rundir/$name" 2>/dev/null || cp "$bin" "$rundir/$name"
    local rc=0
    # -k: plain `timeout` only sends SIGTERM, and a test spinning in a tight
    # loop with no signal handler can ignore it for as long as the machine
    # is up. Four such processes — mutation-test leftovers spinning inside
    # tcpseg_parse's option loop — were found burning a core each, 12 hours
    # after the run that started them. Declaring a hang is not the same as
    # ending it.
    ( cd "$rundir" && timeout -k 5s "${TIMEOUT}s" "./$name" \
        >"$stdout_log" 2>"$stderr_log" ) || rc=$?
    rm -rf "$rundir"

    # Sanitizer-marker scan: ASan "AddressSanitizer:", UBSan
    # "runtime error:" / "UndefinedBehaviorSanitizer:", LSan "LeakSanitizer:".
    #
    # Checked before the timeout so the verdict names the root cause: with
    # halt_on_error=0 a reported error does not stop the program, so a test
    # can report AND then hang, and the report is the actionable half. The
    # hang is not lost — the sentinel makes the report section say so, which
    # matters when the memory bug is fixed and the hang is still there.
    if (( rc == 124 )); then : > "$LOGDIR/$name.timeout"; fi
    if grep -qE "$SAN_MARKERS" "$stderr_log"; then
        echo "$name SAN_FAIL"; return
    fi
    if (( rc == 124 )); then
        echo "$name TIMEOUT"; return
    fi

    # A non-zero exit with no sanitizer report is fine here — several
    # tests exit non-zero deliberately, and the exit code itself is
    # baselined by run_tests.sh; the sanitizers caught nothing.
    echo "$name PASS"
}
export -f run_one_san is_negative_test
export SCRIPT_DIR OUTDIR WORKDIR LOGDIR NURLC RUNTIME CLANG LINK_LIBS TIMEOUT SAN_MARKERS

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
#
# EVERY requested name must exist. Tolerating the missing ones and
# running the rest would let the leak gate quietly shrink — rename one
# pinned test and the gate keeps reporting green over a smaller set,
# which is the failure mode this whole script is being fixed for.
if [[ $# -gt 0 ]]; then
    declare -a filtered=() unknown=()
    for want in "$@"; do
        local_found=0
        for have in "${names[@]}"; do
            [[ "$have" == "$want" ]] && { filtered+=("$have"); local_found=1; break; }
        done
        (( local_found )) || unknown+=("$want")
    done
    if [[ ${#unknown[@]} -gt 0 ]]; then
        echo "ERROR: requested tests do not exist: ${unknown[*]}" >&2; exit 2
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

n_total=0; n_pass=0; n_san_fail=0; n_compile_fail=0; n_link_fail=0
n_skip=0; n_timeout=0
declare -a san_fails=() other_fails=()
while read -r name verdict; do
    n_total=$((n_total + 1))
    case "$verdict" in
        PASS)         n_pass=$((n_pass + 1)) ;;
        SKIP)         n_skip=$((n_skip + 1)) ;;
        SAN_FAIL)     n_san_fail=$((n_san_fail + 1)); san_fails+=("$name") ;;
        TIMEOUT)      n_timeout=$((n_timeout + 1));      other_fails+=("$name TIMEOUT") ;;
        COMPILE_FAIL) n_compile_fail=$((n_compile_fail + 1)); other_fails+=("$name COMPILE_FAIL") ;;
        LINK_FAIL)    n_link_fail=$((n_link_fail + 1));  other_fails+=("$name LINK_FAIL") ;;
    esac
done < "$VERDICTS"

echo
echo "── Sanitized run summary ──"
echo "  total      : $n_total"
echo "  PASS       : $n_pass     (includes tests with non-zero deliberate exit)"
echo "  SKIP       : $n_skip"
echo "  SAN_FAIL   : $n_san_fail     (AddressSanitizer / UBSan / LSan caught a problem)"
echo "  TIMEOUT    : $n_timeout     (did not finish in ${TIMEOUT}s — treat as a hang)"
echo "  COMPILE    : $n_compile_fail"
echo "  LINK       : $n_link_fail"
echo "  logs       : $LOGDIR     (jobs=$JOBS)"
echo

if (( n_san_fail > 0 )); then
    echo "── First sanitizer report from each SAN_FAIL test ──"
    for nm in "${san_fails[@]}"; do
        echo
        echo "▶ $nm"
        [[ -f "$LOGDIR/$nm.timeout" ]] && \
            echo "  (this test ALSO timed out — the hang outlives the report below)"
        head -40 "$LOGDIR/$nm.stderr"
        echo "  …(see $LOGDIR/$nm.stderr for the full report)"
    done
fi

if (( ${#other_fails[@]} > 0 )); then
    echo
    echo "── Tests that did not produce a verdict to sanitize ──"
    printf '  %s\n' "${other_fails[@]}"
fi

# Anything that is not PASS or SKIP fails the run. See the file header:
# scoring on the absence of a sanitizer report is exactly how a hang, a
# broken build and an inverted borrow verdict all read as success.
if (( n_san_fail + n_timeout + n_compile_fail + n_link_fail > 0 )); then
    exit 1
fi

exit 0
