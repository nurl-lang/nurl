#!/usr/bin/env bash
# ============================================================
#  test_skips.sh — which tests this host can run, and with what.
#
#  Sourced by every runner over compiler/tests/ (run_tests.sh,
#  run_san_tests.sh). It answers one question — "can this host run
#  <name> at all?" — and it answers it by asking the TEST, not by
#  consulting a list kept somewhere else.
#
#  ── The declaration ─────────────────────────────────────────────
#  A test states its own requirements on a comment line near the top
#  of its source:
#
#      // requires: live openssl python3
#
#  Tokens:
#     live        exercises real OS facilities — loopback sockets,
#                 unix sockets, threads, signals, subprocesses.
#                 ON by default; NURL_LIVE_TESTS=0 turns it off.
#     fibers      needs the M:N fiber runtime, and pairs a fiber-side
#                 server with a blocking client — so on a platform
#                 where `spawn` is stubbed the test does not print a
#                 wrong answer, it waits forever for a peer that will
#                 never run. Windows is that platform today (no Win64
#                 context-switch backend — docs/ASYNC.md). ON by
#                 default here; NURL_FIBER_TESTS=0 turns it off.
#                 Declare it ONLY for that server/client shape: the
#                 pure fiber tests (async_basic & co) print zeros
#                 instead of hanging, and their Windows goldens pin
#                 exactly that as the known-broken behaviour.
#     internet    contacts a third-party host over the public network.
#                 OFF by default; NURL_HTTP_TESTS=1 or NURL_NET_TESTS=1
#                 turns it on.
#     <anything>  the name of an external command that must be on
#     else        $PATH (curl, python3, openssl, bash …).
#
#  No declaration means the test is pure: no sockets, no subprocesses,
#  no clock races. Pure is the default, and it is the safe default —
#  a test that forgets to declare its socket use fails loudly on a
#  sandboxed host instead of silently never running.
#
#  ── Why declarations and not lists ──────────────────────────────
#  The lists this replaces had drifted in every direction at once,
#  because they lived in the runner and the facts lived in the tests:
#
#    * net_basic binds 127.0.0.1 and ran by default, while net_loopback
#      binds 127.0.0.1 and was gated — the same capability, opposite
#      answers.
#    * http_date and http_jwt open no sockets whatsoever, yet were
#      gated behind NURL_HTTP_TESTS purely for having an http_ prefix.
#      This is the same "gated by name rather than behaviour" defect
#      that was found and fixed for the net_ prefix, one prefix over,
#      still live.
#    * exactly ONE test in the corpus contacts a third party
#      (http_basic → httpbin.org). Everything else the gate was
#      holding back is loopback, threads or unix sockets — none of it
#      needing anything CI does not already have.
#
#  The cost of that drift was the whole live surface of the runtime —
#  threads, channels, semaphores, select, signals, unix sockets, async
#  TCP, the HTTP server, its TLS path, websockets — never running in
#  CI, behind an env var whose name suggests it is about the internet.
#
#  ── One gate, not two ───────────────────────────────────────────
#  The tests used to gate their own live sections a second time, on
#  `env_get NURL_NET_TESTS`, and print a "skipped" line otherwise. That
#  second gate is gone. Two gates for one fact is the same shape as the
#  drift above, one level down: the runner decides whether a test runs
#  at all, and per-test goldens are byte-exact, so a half-run test could
#  never have matched its golden anyway — the "skipped" branches were
#  unreachable in CI, i.e. dead code that only a human reading the file
#  would still believe. A test declares what it needs here, once.
#
#  Contract for callers:
#     is_skipped <name>     non-empty echo means skip
#
#  Env toggles:
#     NURL_LIVE_TESTS=0                    turn off the live tests
#     NURL_FIBER_TESTS=0                   turn off the fiber tests
#     NURL_HTTP_TESTS=1 / NURL_NET_TESTS=1 turn on the internet tests
# ============================================================

# Derived, not inherited: a sourced file that depends on the caller
# having set ROOT_DIR is a trap that fires as a wrong answer (skip
# everything / skip nothing) rather than an error.
NURL_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NURL_TESTS_ROOT="$(cd "$NURL_TESTS_DIR/../.." && pwd)"

ENABLE_LIVE_TESTS="${NURL_LIVE_TESTS:-1}"
ENABLE_FIBER_TESTS="${NURL_FIBER_TESTS:-1}"
# Two spellings because both are already documented and in use across
# the repo (examples/README.md, packages/*/tests). Either means the
# public network is available.
ENABLE_INTERNET_TESTS=0
[[ "${NURL_HTTP_TESTS:-0}" == "1" || "${NURL_NET_TESTS:-0}" == "1" ]] && ENABLE_INTERNET_TESTS=1

# Echo a test's declared requirement tokens, or nothing.
#
# Read from the leading comment block only — a `// requires:` further
# down is prose about something else, not a declaration. The block ends
# at the first line that is neither a comment nor blank, which is the
# real boundary; a fixed line window would silently stop seeing the
# declaration of any test that grew a longer header, and losing a
# declaration means the test runs where it cannot.
test_requires() {
    local src="$NURL_TESTS_DIR/$1.nu"
    [[ -f "$src" ]] || return 0
    awk '/^[[:space:]]*$/ { next }
         /^[[:space:]]*\/\// { if (sub(/^[[:space:]]*\/\/[[:space:]]*requires:[[:space:]]*/, "")) { print; exit } ; next }
         { exit }' "$src"
}

# Decide whether a test is skipped in the current environment.
# Echoes "skip" if so. Kept in sync with run_tests.sh's golden-bijection
# check (skipped tests are exempt from missing/orphan accounting).
is_skipped() {
    local name="$1"
    # Modules imported by other tests: no main(), nothing to run. ASK THE
    # FILE, the way the rest of this script does — the rule used to be a
    # NAME rule (*_mod / *_helper / *_lib), and a name rule silently
    # swallows a real test that happens to end that way. It had:
    # diag_thread_arc_shared_mutation_helper.nu, the regression test for
    # the shared-mutation race one call deep (PR #902), has a main() and
    # has never run once — it had no golden either, and neither the
    # MISSING-golden check nor the ORPHAN check fires for a skipped
    # test, so nothing anywhere said so. The only trace was the SKIP
    # count.
    if [[ -f "$NURL_TESTS_DIR/$name.nu" ]] \
       && ! grep -qE '^@ main( |$)' "$NURL_TESTS_DIR/$name.nu"; then
        echo skip; return
    fi
    # FFI tests whose ext/ module needs an optional native library. build.sh
    # drops a sentinel (stdlib/runtime.<lib>) when pkg-config finds the lib;
    # without it the program legitimately fails to compile ("FFI library X is
    # required ..."). Skip such tests when the sentinel is absent so the corpus
    # self-adapts to a minimal environment (e.g. FreeBSD base, which ships no
    # sqlite3/libpq) instead of spuriously failing on a missing optional dep.
    case "$name" in
        sqlite_*)   [[ -f "$NURL_TESTS_ROOT/stdlib/runtime.sqlite3" ]] || { echo skip; return; } ;;
        postgres_*) [[ -f "$NURL_TESTS_ROOT/stdlib/runtime.pq"      ]] || { echo skip; return; } ;;
        # std/fswatch.nu is Linux-only (inotify is a Linux kernel API; the
        # symbols don't exist to link elsewhere — FreeBSD/macOS CI).
        fswatch_*)  [[ "$(uname -s)" == "Linux" ]] || { echo skip; return; } ;;
    esac

    local tok
    for tok in $(test_requires "$name"); do
        case "$tok" in
            live)     [[ "$ENABLE_LIVE_TESTS"     == "1" ]] || { echo skip; return; } ;;
            fibers)   [[ "$ENABLE_FIBER_TESTS"    == "1" ]] || { echo skip; return; } ;;
            internet) [[ "$ENABLE_INTERNET_TESTS" == "1" ]] || { echo skip; return; } ;;
            # Anything else names an external command the test shells out
            # to. Absent tool → skip, so a stripped host (the FreeBSD CI
            # VM installs neither python3 nor curl) degrades to running
            # less rather than failing on someone else's missing package.
            *)        command -v "$tok" >/dev/null 2>&1 || { echo skip; return; } ;;
        esac
    done
}

# Exported together so a runner that fans out with `xargs -P bash -c`
# gets the whole predicate set in each worker, and cannot half-export it.
export -f is_skipped test_requires
export NURL_TESTS_DIR NURL_TESTS_ROOT \
       ENABLE_LIVE_TESTS ENABLE_FIBER_TESTS ENABLE_INTERNET_TESTS
