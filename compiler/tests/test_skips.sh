#!/usr/bin/env bash
# ============================================================
#  test_skips.sh — which tests are skippable in THIS environment.
#
#  Sourced by every runner over compiler/tests/ (run_tests.sh,
#  run_san_tests.sh). It answers exactly one question:
#
#      "can this host run <name> at all?"
#
#  — network reachability, optional native libraries, platform APIs,
#  and files that are modules rather than tests. It deliberately does
#  NOT answer "does this runner care about <name>", which is a runner's
#  own business: the normal runner baselines should_fail_/diag_
#  diagnostics, the sanitized runner has nothing to say about a program
#  that never links. Those stay local to each runner.
#
#  This file exists because the split was got wrong once. The gating
#  lived inside run_tests.sh, so run_san_tests.sh — a second full pass
#  over the same corpus — silently had none of it, and CI's sanitized
#  job reached httpbin.org on every commit while the normal job in the
#  same workflow skipped those tests by design. Environment knowledge
#  belongs next to the corpus it describes, in one copy.
#
#  Contract for callers: source it, then call `is_skipped <name>`; a
#  non-empty echo means skip. ROOT_DIR is derived here, so sourcing
#  works from any directory.
#
#  Env toggles (read here, once, for every runner):
#     NURL_HTTP_TESTS=1   run the http_ tests that need a live network
#     NURL_NET_TESTS=1    run the tests that open a real socket
# ============================================================

# Derived, not inherited: a sourced file that depends on the caller
# having set ROOT_DIR is a trap that fires as a wrong answer (skip
# everything / skip nothing) rather than an error.
NURL_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NURL_TESTS_ROOT="$(cd "$NURL_TESTS_DIR/../.." && pwd)"

ENABLE_HTTP_TESTS="${NURL_HTTP_TESTS:-0}"
ENABLE_NET_TESTS="${NURL_NET_TESTS:-0}"

# ── HTTP tests are network-dependent; opt-in via env. The handful
#    listed here are pure (parser/builder/router) and run by default
#    even though they share the http_ prefix.
http_runs_by_default() {
    case "$1" in
        http_request_parser|http_response_builder|http_options|http_router|\
        http_static_traversal|http_extras|http_middleware|http_form|\
        http_multipart|http_proxy|http_server_seq|http_server_pipelined|\
        http_server_limits|http_server_tls|http_server_panic|\
        http_binary_body|http_response_binary) return 0 ;;
    esac
    return 1
}
http_needs_net() {
    case "$1" in
        http_server_seq|http_server_pipelined|http_server_limits|\
        http_server_tls|http_server_panic|http_binary_body|\
        http_response_binary) return 0 ;;
    esac
    return 1
}

# Same idea for the net_ prefix: gate on what a test actually DOES,
# not on its name. Most net_ tests are pure wire-format / state-machine
# logic (the sans-IO stack) and must run on every commit — that is the
# whole point of writing them sans-IO. Only the ones that open a real
# socket are opt-in.
#
# Listing the socket-using tests explicitly, rather than exempting the
# offline ones one by one, keeps the default SAFE: a new net_ test runs
# by default, and a test that forgets to declare its socket use fails
# loudly on a sandboxed host instead of silently never running.
net_needs_net() {
    case "$1" in
        net_loopback) return 0 ;;
    esac
    return 1
}

# Decide whether a test is skipped in the current environment.
# Echoes "skip" if so. Kept in sync with run_tests.sh's golden-bijection
# check (skipped tests are exempt from missing/orphan accounting).
is_skipped() {
    local name="$1"
    # Helper modules imported by other tests: no main(), nothing to run.
    case "$name" in *_mod|*_helper|*_lib) echo skip; return ;; esac
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
    if [[ "$name" == http_* ]]; then
        if ! http_runs_by_default "$name" && [[ "$ENABLE_HTTP_TESTS" != "1" ]]; then
            echo skip; return
        fi
        if http_needs_net "$name" && [[ "$ENABLE_NET_TESTS" != "1" ]]; then
            echo skip; return
        fi
    fi
    if [[ "$name" == net_* ]] && net_needs_net "$name" && [[ "$ENABLE_NET_TESTS" != "1" ]]; then
        echo skip; return
    fi
}

# Exported together so a runner that fans out with `xargs -P bash -c`
# gets the whole predicate set in each worker, and cannot half-export it.
export -f is_skipped http_runs_by_default http_needs_net net_needs_net
export NURL_TESTS_DIR NURL_TESTS_ROOT ENABLE_HTTP_TESTS ENABLE_NET_TESTS
