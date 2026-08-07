#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu_riscv64_tests.sh — the RV64 guest gate.
#
#  The same programs the x86_64 guest gate boots, on the other
#  architecture: corpus tests against their ORDINARY hosted goldens
#  (the whole claim of the port is that nothing above the bottom edge
#  changed), then the guest-only demos that need a device.
#
#  Usage:  run_qemu_riscv64_tests.sh [name …]     (default: all)
#
#  Skips itself, loudly, when qemu-system-riscv64 is absent — the same
#  contract the x86 gate has, so a developer without it still gets a
#  green run of everything else.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
OUTDIR="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel-riscv64}"
QEMU="${QEMU_RISCV64:-${QEMU:-qemu-system-riscv64}}"

command -v "$QEMU" >/dev/null 2>&1 || {
    echo "run_qemu_riscv64_tests.sh: $QEMU not found — skipping the RV64 guest gate"
    exit 0
}
[ -x "$ROOT/build/nurlc" ] || { echo "run ./build.sh first" >&2; exit 2; }

build() { NURL_UNIKERNEL_OUT="$OUTDIR" "$ROOT/unikernel/build_unikernel_riscv64.sh" "$@"; }
boot()  { "$ROOT/unikernel/run_qemu_riscv64.sh" "$@"; }

names=("$@")
[ ${#names[@]} -gt 0 ] || names=(hello vec_basic float_format
                                 net_socket net_tcpstack
                                 async_basic async_chan async_mn async_sleep)

fails=0
for name in "${names[@]}"; do
    golden="$TESTS/outputs/$name.txt"
    [ -f "$golden" ] || { echo "SKIP $name (no golden)"; continue; }
    if ! build "$TESTS/$name.nu" >/dev/null 2>&1; then
        echo "FAIL $name (build)"; fails=$((fails + 1)); continue
    fi
    want_exit=$(sed -n 's/^EXIT //p' "$golden" | head -1)
    want_out=$(sed -n '/^OUTPUT$/,$p' "$golden" | tail -n +2)
    got_out=$(boot "$OUTDIR/$name.elf" -t 120 2>&1)
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
demos=0
if [ $# -eq 0 ]; then
    for demo in devices netdev dhcp loopback; do
        src="$ROOT/unikernel/demos/$demo.nu"
        # A machine-specific expectation when the machines genuinely
        # differ, the shared one otherwise. `virt` publishes 32 static
        # virtio-mmio slots and fills them from the top; microvm
        # publishes exactly the devices that exist. A demo that reports
        # what it found is right on both, and the difference belongs in
        # the expectation, not in the demo.
        exp="$ROOT/unikernel/demos/$demo.riscv64.expected"
        [ -f "$exp" ] || exp="$ROOT/unikernel/demos/$demo.expected"
        [ -f "$src" ] && [ -f "$exp" ] || continue
        demos=$((demos + 1))
        if ! build "$src" >/dev/null 2>&1; then
            echo "FAIL $demo (build)"; fails=$((fails + 1)); continue
        fi
        # virt's virtio-mmio slots are in the device tree; the guest
        # finds them there instead of on a command line.
        got=$(boot "$OUTDIR/$demo.elf" -t 120 -- \
                -netdev user,id=n0 -device virtio-net-device,netdev=n0 2>&1)
        if [ "$got" = "$(cat "$exp")" ]; then
            echo "PASS $demo (guest-only demo)"
        else
            echo "FAIL $demo"
            diff <(cat "$exp") <(printf '%s\n' "$got") | head -8 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    done

    # A fault must be REPORTED, not silently survived — the property
    # the x86 pass proved matters most, checked here from the start.
    demos=$((demos + 1))
    if build "$ROOT/unikernel/demos/fault.nu" >/dev/null 2>&1; then
        nullout=$(NURL_APPEND='args="null 0"' boot "$OUTDIR/fault.elf" -t 60 2>&1)
        nullrc=$?
        stackout=$(NURL_APPEND='args="stack 100000000"' boot "$OUTDIR/fault.elf" -t 60 2>&1)
        stackrc=$?
        if [ "$nullrc" = 126 ] && [ "$stackrc" = 126 ] \
           && printf '%s' "$nullout" | grep -q "nurl: fault" \
           && printf '%s' "$stackout" | grep -q "nurl: fault"; then
            echo "PASS fault (both faults reported, exit 126)"
        else
            echo "FAIL fault (null exit $nullrc, stack exit $stackrc)"
            printf '%s\n' "$nullout" | head -3 | sed 's/^/     /'
            printf '%s\n' "$stackout" | head -3 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    else
        echo "FAIL fault (build)"; fails=$((fails + 1))
    fi

    # Entropy from a device, because this ISA has no instruction for
    # it: with `-device virtio-rng-device` a draw must return bytes
    # that are neither all zero nor equal to the next draw, and WITHOUT
    # the device the guest must refuse by name rather than invent
    # anything. Both halves matter — a fake entropy source passes the
    # first check and fails nothing.
    demos=$((demos + 1))
    if build "$ROOT/unikernel/tests/entropy_rv.nu" >/dev/null 2>&1; then
        withdev=$(boot "$OUTDIR/entropy_rv.elf" -t 120 -- -device virtio-rng-device 2>&1)
        wrc=$?
        nodev=$(boot "$OUTDIR/entropy_rv.elf" -t 120 2>&1)
        nrc=$?
        # The two ways a FAKE source looks plausible are the ones the
        # guest counts: a draw that is ALL zeroes (a device that
        # answered without writing), and two draws that are IDENTICAL
        # (a constant, or one buffer read twice). So the thresholds are
        # 32, not 0.
        #
        # Asserting zeros=0 and same_bytes=0 — "no byte is zero, and no
        # position matches" — is not a property of randomness but of
        # unlikely randomness. With 32 uniform bytes each has
        # probability 1-(255/256)^32 = 11.8%, so the gate rejected
        # CORRECT entropy on ~22% of runs, about one in 4.5. That is
        # what it was doing: the same commit passed and failed hours
        # apart with nothing between the two runs but the dice.
        wz=$(printf '%s' "$withdev" | sed -n 's/^zeros=\([0-9]*\)$/\1/p')
        ws=$(printf '%s' "$withdev" | sed -n 's/^same_bytes=\([0-9]*\)$/\1/p')
        if [ "$wrc" = 0 ] \
           && [ -n "$wz" ] && [ "$wz" != 32 ] \
           && [ -n "$ws" ] && [ "$ws" != 32 ] \
           && [ "$nrc" = 127 ] \
           && printf '%s' "$nodev" | grep -q 'virtio-rng'; then
            echo "PASS entropy (device gives bytes; absence is refused by name)"
        else
            echo "FAIL entropy (with-device exit $wrc, without exit $nrc; zeros=${wz:-?}/32, same_bytes=${ws:-?}/32 — 32 means a fake source)"
            printf '%s\n' "$withdev" | head -4 | sed 's/^/     /'
            printf '%s\n' "$nodev" | head -2 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    else
        echo "FAIL entropy (build)"; fails=$((fails + 1))
    fi

    # An HTTP server in the guest, answering a client on the host.
    if command -v curl >/dev/null 2>&1; then
        demos=$((demos + 1))
        if build "$ROOT/unikernel/demos/httpd.nu" >/dev/null 2>&1; then
            out=$(mktemp)
            ( boot "$OUTDIR/httpd.elf" -t 120 -- \
                -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18773-:8080 \
                -device virtio-net-device,netdev=n0 > "$out" 2>&1 ) &
            qpid=$!
            body=""
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                sleep 3
                body=$(curl -sS --max-time 10 http://127.0.0.1:18773/ 2>/dev/null)
                [ -n "$body" ] && break
            done
            kill $qpid 2>/dev/null; wait $qpid 2>/dev/null
            if printf '%s' "$body" | grep -q "hello from a guest"; then
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
fi

total=$(( ${#names[@]} + demos ))
echo "── QEMU RV64 guest run: $(( total - fails ))/$total ──"
exit $(( fails > 0 ? 1 : 0 ))
