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
#                 never run (docs/ASYNC.md lists the platforms with a
#                 switch backend; every hosted runner has one). ON by
#                 default here; NURL_FIBER_TESTS=0 turns it off.
#                 Declare it ONLY for that server/client shape.
#     internet    contacts a third-party host over the public network.
#                 OFF by default; NURL_HTTP_TESTS=1 or NURL_NET_TESTS=1
#                 turns it on.
#     cpu-aes     runs the hardware crypto tier (nurl_v128_aes*,
#                 nurl_v128_clmul_*; docs/spec.md §4.1b): an x86-64 CPU
#                 with AES-NI and PCLMULQDQ, or an AArch64 one with the
#                 ARMv8 Cryptographic Extension's AES and PMULL (every
#                 Apple Silicon and Graviton CPU). Without it the program
#                 takes its software path or panics at the tier's gate,
#                 and the golden — written on such a CPU — cannot match.
#                 NURL_CPU_AES=0 turns it off, as it does in the runtime.
#     cpu-vaes    runs the VAES tier (nurl_v256_aes*, nurl_v256_clmul_*):
#                 x86-64-v3 with VAES and VPCLMULQDQ (Ice Lake / Zen 3
#                 and later). NURL_CPU_VAES=0 turns it off.
#     cpu-vaes512 runs the AVX-512 VAES tier (nurl_v512_aes*,
#                 nurl_v512_clmul_*): the VAES tier plus x86-64-v4.
#                 NURL_CPU_VAES512=0 turns it off.
#     cpu-ifma    runs the IFMA tier (nurl_v256_madd52lo / _hi):
#                 x86-64-v4 with AVX-512 IFMA (Ice Lake / Zen 4 and
#                 later). NURL_CPU_IFMA=0 turns it off.
#                 Unlike cpu-aes, none of these is assumed where the host
#                 cannot be asked: most x86-64 machines lack them.
#     ktls        hands TLS 1.3 record protection to the kernel (std/tls.nu
#                 tls_ktls): Linux 6.14+ (KeyUpdate in both directions)
#                 with the `tls` ULP available — the module loaded, since
#                 an unprivileged process cannot load it. NURL_KTLS_TESTS=0
#                 turns it off.
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

# Fixture intent precedes host capability checks. Explicit module headers
# distinguish imported helpers even when their names begin diag_/should_fail_.
# Existing COMPILE FAIL goldens also cover negative tests without a prefix.
test_mode() {
    local name="$1" declared first gold="$NURL_TESTS_DIR/outputs/$1.txt"
    declared=$(awk '/^[[:space:]]*$/ { next }
        /^[[:space:]]*\/\// {
            if (sub(/^[[:space:]]*\/\/[[:space:]]*fixture:[[:space:]]*/, "")) {
                sub(/[;[:space:]].*$/, ""); print; exit
            }
            next
        }
        { exit }' "$NURL_TESTS_DIR/$name.nu")
    if [[ -n "$declared" ]]; then echo "$declared"; return; fi
    case "$name" in
        diag_*|borrow_*|should_fail_*|arity_strict_*) echo reject; return ;;
        lint_*) echo compile; return ;;
    esac
    if [[ -f "$gold" ]]; then
        IFS= read -r first < "$gold"
        if [[ "${first%$'\r'}" == 'COMPILE FAIL' ]]; then echo reject; return; fi
    fi
    echo run
}

# Decide whether a test is skipped in the current environment.
# Echoes "skip" if so. Kept in sync with run_tests.sh's golden-bijection
# check (skipped tests are exempt from missing/orphan accounting).
is_skipped() {
    local name="$1"
    # Helpers declare their intent. Missing main is also a valid parser
    # rejection fixture, and a filename suffix can belong to a real test.
    if [[ "$(test_mode "$name")" == module ]]; then
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
        # setrlimit(RLIMIT_NOFILE) numbered as on Linux.
        fdlimit_*)  [[ "$(uname -s)" == "Linux" ]] || { echo skip; return; } ;;
        # Its black hole is Linux dropping SYNs to a full accept queue;
        # FreeBSD answers the same connect another way.
        net_connect_fiber_timeout) [[ "$(uname -s)" == "Linux" ]] || { echo skip; return; } ;;
        # Its bound holds where a busy worker polls I/O itself (Linux's
        # netpoller). Elsewhere a dedicated reactor thread polls, and the
        # delay is that thread's wait for a time slice: 4070 dispatches
        # on the FreeBSD CI VM, nothing to do with the run queue (agora
        # #137).
        sched_accept_admission) [[ "$(uname -s)" == "Linux" ]] || { echo skip; return; } ;;
        # Hundreds of sockets open at once: past macOS's default limit of
        # 256 descriptors per process.
        reactor_many_waiters|udp_bind_ephemeral_distinct) [[ "$(uname -s)" != "Darwin" ]] || { echo skip; return; } ;;
    esac

    local tok
    for tok in $(test_requires "$name"); do
        case "$tok" in
            cpu-aes)  host_has_cpu_aes || { echo skip; return; } ;;
            cpu-vaes) host_has_cpu_vaes || { echo skip; return; } ;;
            cpu-vaes512) host_has_cpu_vaes512 || { echo skip; return; } ;;
            cpu-ifma) host_has_cpu_ifma || { echo skip; return; } ;;
            ktls)     host_has_ktls || { echo skip; return; } ;;
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

# The `ktls` requirement: the `tls` ULP is available and the kernel is
# 6.14 or later (what nurl_ktls_supported asks).
host_has_ktls() {
    [[ "${NURL_KTLS_TESTS:-1}" == "0" ]] && return 1
    [[ "$(uname -s)" == "Linux" ]] || return 1
    grep -qw tls /proc/sys/net/ipv4/tcp_available_ulp 2>/dev/null || return 1
    local rel maj min
    rel=$(uname -r); maj=${rel%%.*}; min=${rel#*.}; min=${min%%[!0-9]*}
    (( maj > 6 || (maj == 6 && min >= 14) ))
}

# The `cpu-aes` requirement: x86-64 with AES-NI and PCLMULQDQ, the
# feature bits nurl_cpu_x86_aes tests (its x86-64-v2 bits come with
# every AES-NI CPU), or AArch64 with AES and PMULL, what nurl_cpu_arm_aes
# tests (/proc/cpuinfo's `Features: … aes pmull …`). Where /proc/cpuinfo
# is not there to ask (FreeBSD, macOS) the host is taken to have it — an
# x86-64 one this project's CI runs on does, every Apple Silicon Mac
# does (hw.optional.arm.FEAT_AES says so where macOS has the key), and
# the test itself prints which path ran.
host_has_cpu_aes() {
    [[ "${NURL_CPU_AES:-1}" == "0" ]] && return 1
    case "$(uname -m)" in
        x86_64|amd64)
            if [[ -r /proc/cpuinfo ]]; then
                grep -qw aes /proc/cpuinfo && grep -qw pclmulqdq /proc/cpuinfo
                return
            fi
            return 0 ;;
        aarch64|arm64)
            if [[ -r /proc/cpuinfo ]]; then
                grep -m1 '^Features' /proc/cpuinfo | grep -qw aes &&
                    grep -m1 '^Features' /proc/cpuinfo | grep -qw pmull
                return
            fi
            if [[ "$(uname -s)" == Darwin ]]; then
                [[ "$(sysctl -n hw.optional.arm.FEAT_AES 2>/dev/null || echo 1)" == 1 ]]
                return
            fi
            return 0 ;;
    esac
    return 1
}

# The CPU flags the host reports, lower-case and space-separated: Linux
# /proc/cpuinfo, or the sysctl feature words of an Intel Mac. Empty
# where neither answers.
host_cpu_flags() {
    if [[ -r /proc/cpuinfo ]]; then
        grep -m1 -E '^(flags|Features)' /proc/cpuinfo | cut -d: -f2
        return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n machdep.cpu.features machdep.cpu.leaf7_features 2>/dev/null |
            tr 'A-Z\n' 'a-z '
    fi
}

host_has_flags() {  # host_has_flags <flag>...: every one is reported
    local f fl
    fl=" $(host_cpu_flags) "
    for f in "$@"; do [[ "$fl" == *" $f "* ]] || return 1; done
}

# The `cpu-vaes` requirement: what nurl_cpu_x86_vaes tests — AVX2 (the
# rest of x86-64-v3 comes with it on every VAES CPU), the AES tier, VAES
# and VPCLMULQDQ.
host_has_cpu_vaes() {
    host_has_cpu_aes || return 1
    [[ "${NURL_CPU_VAES:-1}" == "0" || "${NURL_CPU_V3:-1}" == "0" ]] && return 1
    host_has_flags avx2 vaes vpclmulqdq
}

# The `cpu-vaes512` requirement: that plus x86-64-v4's AVX-512 subsets.
host_has_cpu_vaes512() {
    host_has_cpu_vaes || return 1
    [[ "${NURL_CPU_VAES512:-1}" == "0" ]] && return 1
    host_has_flags avx512f avx512bw avx512cd avx512dq avx512vl
}

# The `cpu-ifma` requirement: what nurl_cpu_x86_ifma tests — x86-64-v4
# (AVX2 standing in for the rest of v3, as above) and AVX-512 IFMA. Not
# on the AES chain.
host_has_cpu_ifma() {
    [[ "${NURL_CPU_IFMA:-1}" == "0" || "${NURL_CPU_V3:-1}" == "0" ]] && return 1
    host_has_flags avx2 avx512f avx512bw avx512cd avx512dq avx512vl avx512ifma
}

# Exported together so a runner that fans out with `xargs -P bash -c`
# gets the whole predicate set in each worker, and cannot half-export it.
export -f is_skipped test_requires test_mode host_has_cpu_aes host_has_ktls \
    host_cpu_flags host_has_flags host_has_cpu_vaes host_has_cpu_vaes512     host_has_cpu_ifma
export NURL_TESTS_DIR NURL_TESTS_ROOT \
       ENABLE_LIVE_TESTS ENABLE_FIBER_TESTS ENABLE_INTERNET_TESTS
