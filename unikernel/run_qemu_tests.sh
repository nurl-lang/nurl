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
[ ${#names[@]} -gt 0 ] || names=(hello vec_basic float_format
                                 net_socket net_tcpstack
                                 async_basic async_chan async_mn async_sleep)

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
    for demo in devices netdev dhcp; do
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

# ── the MCP endpoint, spoken to as a client would ───────────────
# Three requests, because one would not distinguish "the server
# answered" from "the server answered correctly": initialize settles
# the protocol, tools/list settles the catalogue, and tools/call
# settles that a tool actually ran and its output came back.
if [ $# -eq 0 ] && command -v curl >/dev/null 2>&1; then
    demos=$((demos + 1))
    if "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/mcpd.nu" >/dev/null 2>&1; then
        out=$(mktemp)
        ( "$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/mcpd.elf" -t 120 -- \
            -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18771-:18770 \
            -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
        qpid=$!
        init=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            sleep 2
            init=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                   -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"gate","version":"1"}}}' \
                   http://127.0.0.1:18771/mcp 2>/dev/null)
            [ -n "$init" ] && break
        done
        tools=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
                http://127.0.0.1:18771/mcp 2>/dev/null)
        called=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
                 -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"from the host"}}}' \
                 http://127.0.0.1:18771/mcp 2>/dev/null)
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

echo "── QEMU guest run: $((${#names[@]} + demos - fails))/$((${#names[@]} + demos)) ──"
[ "$fails" -eq 0 ]
