#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu_tests.sh — run corpus tests INSIDE the guest and
#  compare against the same goldens the hosted runner uses.
#
#  Usage:  unikernel/run_qemu_tests.sh [name …]     (default: the list below)
#
#  The list is short on purpose. The nolibc corpus runner already
#  proves 449 tests against these goldens with no libc; what a QEMU run
#  adds is the bottom edge — the boot path, the UART, the memory map
#  the hypervisor reported, the TSC — so the tests here are chosen to
#  exercise those and nothing else twice:
#
#    hello        the whole print path, and an exit code that gets out
#    vec_basic    the allocator against the guest's memory map
#    float_format the software float formatter, on a machine whose SSE
#                 state the boot stub enabled by hand
#    net_socket   the sans-IO stack, the socket layer and the loopback,
#                 all of it, on bare metal
#    net_tcpstack the connection table, likewise
#    async_*      the cooperative scheduler on stacks whose guard pages
#                 are real page-table entries, and — async_sleep — the
#                 TSC, which is the one clock this machine has
#
#  Requires qemu-system-x86_64; skips (exit 0) with a message when it
#  is absent, because a developer without QEMU should still be able to
#  run the rest of the gates.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
QEMU="${QEMU:-qemu-system-x86_64}"

command -v "$QEMU" >/dev/null 2>&1 || {
    echo "run_qemu_tests.sh: $QEMU not found — skipping the guest gate"
    exit 0
}

names=("$@")
# The corpus this gate boots. The four SIMD entries are here because
# `v128` is the one part of the language whose CODEGEN differs per
# architecture: `nurl_v128_eqmask8` is a `pmovmskb` on x86-64 and a
# shift-and-narrow sequence on AArch64, a scalarised loop where there is
# no vector unit at all, and an `align 1` vector load is a different
# instruction on each. Every one of them compares against the SAME hosted
# golden, so a lane order or a bit order that came out backwards on one
# ISA fails here rather than in someone's TLS session. simd_scan and
# wide_arith check the primitives against scalar references,
# chacha20_simd_agree checks the vector cipher against the scalar one at
# every length, and http_request_parser is the head parser those scanners
# are actually under. Four seconds, all told, under TCG.
[ ${#names[@]} -gt 0 ] || names=(hello vec_basic float_format
                                 net_socket net_tcpstack
                                 async_basic async_chan async_mn async_sleep
                                 simd_scan wide_arith chacha20_simd_agree
                                 http_request_parser)

fails=0
for name in "${names[@]}"; do
    golden="$TESTS/outputs/$name.txt"
    [ -f "$golden" ] || { echo "SKIP $name (no golden)"; continue; }
    if ! "$ROOT/unikernel/build_unikernel.sh" "$TESTS/$name.nu" >/dev/null 2>&1; then
        echo "FAIL $name (build)"; fails=$((fails + 1)); continue
    fi
    want_exit=$(sed -n 's/^EXIT //p' "$golden" | head -1)
    want_out=$(sed -n '/^OUTPUT$/,$p' "$golden" | tail -n +2)
    got_out=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/$name.elf" -t 60 2>&1)
    got_exit=$?
    if [ "$got_out" = "$want_out" ] && [ "$got_exit" = "$want_exit" ]; then
        echo "PASS $name"
    else
        echo "FAIL $name (exit $got_exit, want ${want_exit:-?})"
        diff <(printf '%s\n' "$want_out") <(printf '%s\n' "$got_out") | head -6 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
done

# ── the demos, which only exist in the guest ────────────────────
# A corpus test cannot cover these: they talk to hardware, so there is
# no hosted golden to compare against and no host on which to produce
# one. Each demo carries its own expected output beside it, and the
# QEMU arguments it needs are named here — a virtio-net device for the
# one that goes looking for devices.
demos=0
if [ $# -eq 0 ]; then
    for demo in devices netdev dhcp loopback; do
        src="$ROOT/unikernel/demos/$demo.nu"
        exp="$ROOT/unikernel/demos/$demo.expected"
        [ -f "$src" ] && [ -f "$exp" ] || continue
        demos=$((demos + 1))
        if ! "$ROOT/unikernel/build_unikernel.sh" "$src" >/dev/null 2>&1; then
            echo "FAIL $demo (build)"; fails=$((fails + 1)); continue
        fi
        got=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/$demo.elf" -t 60 -- \
              -netdev user,id=n0 -device virtio-net-device,netdev=n0 2>&1)
        if [ "$got" = "$(cat "$exp")" ]; then
            echo "PASS $demo (guest-only demo)"
        else
            echo "FAIL $demo"
            diff "$exp" <(printf '%s\n' "$got") | head -6 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    done
fi

# ── the machine's own failure report ────────────────────────────
# Every other gate here checks that something worked. This one checks
# what happens when something does not: a guest with no IDT answers a
# null dereference by shutting down silently, which from the host is
# indistinguishable from a clean exit. Two faults, two reports, one
# distinct exit code — 126, which is neither a panic (127) nor anything
# a program can return.
if [ $# -eq 0 ]; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/fault.nu" >/dev/null 2>&1; then
        nullout=$(NURL_APPEND='args="null 0"' \
                  "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/fault.elf" -t 60 2>&1)
        nullcode=$?
        stackout=$(NURL_APPEND='args="stack 100000000"' \
                   "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/fault.elf" -t 60 2>&1)
        stackcode=$?
        ok=1
        # A null store must be a page fault at address zero, not a quiet
        # write to physical page zero — which is what an identity-mapped
        # guest does until the page is unmapped on purpose.
        printf '%s' "$nullout" | grep -q '#PF page fault' || ok=0
        printf '%s' "$nullout" | grep -q 'cr2=0x0 (not present) on write' || ok=0
        [ "$nullcode" = 126 ] || ok=0
        # A recursion past the end of the boot stack must be a fault on
        # its guard page, reported from the IST stack — the ordinary one
        # is exactly what ran out.
        printf '%s' "$stackout" | grep -q '#PF page fault' || ok=0
        [ "$stackcode" = 126 ] || ok=0
        if [ "$ok" = 1 ]; then
            echo "PASS fault (both faults reported, exit 126)"
        else
            echo "FAIL fault (null exit $nullcode, stack exit $stackcode)"
            printf '%s\n' "$nullout" | head -4 | sed 's/^/     /'
            printf '%s\n' "$stackout" | head -4 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    else
        echo "FAIL fault (build)"; fails=$((fails + 1))
    fi
fi

# ── the smallest machine it still works on ──────────────────────
# Everything else here runs with 256 MiB, which hides the question a
# density-minded operator actually asks. The floor was measured — hello
# answers on 3 MiB, the HTTP server on 4 — and these run with headroom
# over it, so what this gate really pins is APPETITE: a change that
# doubles what the guest needs before it can answer fails here rather
# than on somebody's Firecracker host.
#
# The last case is the one that matters most: below the floor the
# machine must say so. A guest that quietly wanders off is what the
# memory work in this directory was about.
if [ $# -eq 0 ]; then
    demos=$((demos + 1))
    ok=1
    "$ROOT/unikernel/build_unikernel.sh" "$TESTS/hello.nu" >/dev/null 2>&1 || ok=0
    small=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/hello.elf" -t 60 -- -m 4 2>&1)
    printf '%s' "$small" | grep -q 'Hello, NURL!' || ok=0

    tiny=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/hello.elf" -t 60 -- -m 2 2>&1)
    tinycode=$?
    printf '%s' "$tiny" | grep -q 'no usable memory above the image' || ok=0
    [ "$tinycode" = 127 ] || ok=0

    # A program that asks for more fibers than the machine can hold must
    # SAY so. async_mn wants 500 of them at 68 KiB each; on 4 MiB it used
    # to get eleven, print the count of the eleven as though that were
    # the answer, and exit 0.
    "$ROOT/unikernel/build_unikernel.sh" "$TESTS/async_mn.nu" >/dev/null 2>&1 || ok=0
    fibers=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/async_mn.elf" -t 60 -- -m 4 2>&1)
    fiberscode=$?
    printf '%s' "$fibers" | grep -q 'cannot create a fiber' || ok=0
    [ "$fiberscode" = 134 ] || ok=0

    if command -v curl >/dev/null 2>&1; then
        "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/httpd.nu" >/dev/null 2>&1 || ok=0
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/httpd.elf" -t 90 -- -m 8 \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18099-:8080 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        body=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            body=$(curl -sS --max-time 8 http://127.0.0.1:18099/ 2>/dev/null)
            [ -n "$body" ] && break
        done
        wait $qpid
        [ "$body" = "hello from a guest" ] || ok=0
        rm -f "$out"
    fi

    if [ "$ok" = 1 ]; then
        echo "PASS smallmem (4 MiB hello, 8 MiB server, 2 MiB and 500 fibers say why not)"
    else
        echo "FAIL smallmem"
        printf '%s\n' "$tiny" | head -3 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
fi

# ── the demo with a filesystem and arguments ────────────────────
# Built with --fs, run with args on the kernel command line: the two
# halves of B7, and the only demo whose build and invocation differ
# from the rest.
if [ $# -eq 0 ]; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" --fs "$ROOT/unikernel/demos/initfs_root" \
            "$ROOT/unikernel/demos/initfs.nu" >/dev/null 2>&1; then
        got=$(NURL_APPEND='args="--token abc --verbose"' \
              "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/initfs.elf" -t 60 2>&1)
        if [ "$got" = "$(cat "$ROOT/unikernel/demos/initfs.expected")" ]; then
            echo "PASS initfs (guest-only demo)"
        else
            echo "FAIL initfs"
            diff "$ROOT/unikernel/demos/initfs.expected" <(printf '%s\n' "$got") | head -6 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    else
        echo "FAIL initfs (build)"; fails=$((fails + 1))
    fi
fi

# ── the one demo with a client on the other end ─────────────────
# The rest of the gate reads what the guest printed. This one needs
# something to talk TO it, through QEMU's port forward, which is the
# whole point: the server is in the guest and the client is not on the
# machine at all.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/httpd.nu" >/dev/null 2>&1; then
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/httpd.elf" -t 90 -- \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18080-:8080 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        # The guest boots, then leases an address, and only then
        # binds. Retry rather than guess how long that takes on a
        # machine running QEMU under TCG.
        body=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            body=$(curl -sS --max-time 8 http://127.0.0.1:18080/ 2>/dev/null)
            [ -n "$body" ] && break
        done
        wait $qpid
        if [ "$body" = "hello from a guest" ] && grep -q "response written" "$out"; then
            echo "PASS httpd (guest server, host client)"
        else
            echo "FAIL httpd (curl got \"$body\")"
            head -6 "$out" | sed 's/^/     /'
            fails=$((fails + 1))
        fi
        rm -f "$out"
    else
        echo "FAIL httpd (build)"; fails=$((fails + 1))
    fi
fi

# ── the same server, two hundred times ──────────────────────────
# The httpd gate proves a request can be answered. This one proves the
# two-hundredth can, which is a different property and the one an
# appliance is judged on: a leak per packet is invisible in a demo and
# fatal in a machine that runs for a week. The guest reports its own
# page allocator's numbers and reaches the verdict itself — the harness
# only reads it, because nothing outside the guest can see its heap.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/soak.nu" >/dev/null 2>&1; then
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/soak.elf" -t 300 -- \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18090-:8080 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            curl -sS --max-time 8 http://127.0.0.1:18090/ >/dev/null 2>&1 && break
        done
        # Ten more than the guest will answer: the port forward accepts
        # before the guest listens, so the first few may never arrive.
        for _ in $(seq 1 210); do
            curl -sS --max-time 8 http://127.0.0.1:18090/ >/dev/null 2>&1
        done
        wait $qpid
        if grep -q 'verdict STABLE' "$out"; then
            echo "PASS soak ($(sed -n 's/.*answered \([0-9]*\) requests/\1/p' "$out" | tail -1) requests, heap flat)"
        else
            echo "FAIL soak"
            grep -E 'soak:' "$out" | tail -6 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
        rm -f "$out"
    else
        echo "FAIL soak (build)"; fails=$((fails + 1))
    fi
fi

# ── the MCP endpoint, spoken to as a client would ───────────────
# HOST PORTS HERE MUST NOT BE PORTS THE CORPUS BINDS. This gate used to
# forward 18771, which `compiler/tests/http_server_limits.nu` listens on:
# run the two suites on one machine and one of them fails with
# NetAddrInUse, in a test that has nothing to do with either change.
# Three requests, because one would not distinguish "the server
# answered" from "the server answered correctly": initialize settles
# the protocol, tools/list settles the catalogue, and tools/call
# settles that a tool actually ran and its output came back.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/mcpd.nu" >/dev/null 2>&1; then
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/mcpd.elf" -t 120 -- \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18992-:18770 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        init=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            init=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                   -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"gate","version":"1"}}}' \
                   http://127.0.0.1:18992/mcp 2>/dev/null)
            [ -n "$init" ] && break
        done
        tools=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
                http://127.0.0.1:18992/mcp 2>/dev/null)
        called=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                 -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"from the host"}}}' \
                 http://127.0.0.1:18992/mcp 2>/dev/null)
        kill $qpid 2>/dev/null; wait $qpid 2>/dev/null
        if printf '%s' "$init" | grep -q '"protocolVersion"' \
           && printf '%s' "$tools" | grep -q '"echo"' \
           && printf '%s' "$called" | grep -q 'from the host'; then
            echo "PASS mcpd (MCP endpoint in the guest, client on the host)"
        else
            echo "FAIL mcpd"
            printf '     init=%.90s\n     tools=%.90s\n     call=%.90s\n' "$init" "$tools" "$called"
            head -4 "$out" | sed 's/^/     /'
            fails=$((fails + 1))
        fi
        rm -f "$out"
    else
        echo "FAIL mcpd (build)"; fails=$((fails + 1))
    fi
fi

# ── TLS, which needs a certificate that is not in the repo ──────
# Generated here rather than committed: a private key in a git history
# is a private key forever, even a throwaway one, and `openssl req` is
# already required by the corpus's own TLS test.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    demos=$((demos + 1))
    tlsdir=$(mktemp -d)
    mkdir -p "$tlsdir/etc/tls"
    openssl req -x509 -newkey rsa:2048 -keyout "$tlsdir/etc/tls/key.pem" \
        -out "$tlsdir/etc/tls/cert.pem" -days 3650 -nodes -subj "/CN=nurl-guest" \
        >/dev/null 2>&1
    if "$ROOT/unikernel/build_unikernel.sh" --fs "$tlsdir" \
            "$ROOT/unikernel/demos/httpsd.nu" >/dev/null 2>&1; then
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/httpsd.elf" -t 120 -- \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18443-:8443 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        body=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 3
            body=$(curl -sS --insecure --max-time 10 https://127.0.0.1:18443/ 2>/dev/null)
            [ -n "$body" ] && break
        done
        wait $qpid
        if [ "$body" = "hello from a guest over TLS" ]; then
            echo "PASS httpsd (TLS 1.3 in the guest, curl on the host)"
        else
            echo "FAIL httpsd (curl got \"$body\")"
            head -6 "$out" | sed 's/^/     /'
            fails=$((fails + 1))
        fi
        rm -f "$out"
    else
        echo "FAIL httpsd (build)"; fails=$((fails + 1))
    fi
    rm -rf "$tlsdir"
fi

# ── B10: the swarm-mcp appliance — the plan's endpoint milestone ──
# The same package that runs hosted boots as the guest, joins the
# cluster through the relay leg, and completes an expression task and
# a compiled-wasm task (run in-process on the pure-NURL wasmtime — a
# guest has no processes). swarm_gate.sh prints its own detail lines,
# including the measured cold-start-to-first-answer figure.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/tests/swarm_gate.sh"; then
        echo "PASS swarm appliance (B10: census + expr + wasm in the guest)"
    else
        echo "FAIL swarm appliance"; fails=$((fails + 1))
    fi
fi

echo "── QEMU guest run: $((${#names[@]} + demos - fails))/$((${#names[@]} + demos)) ──"
[ "$fails" -eq 0 ]
