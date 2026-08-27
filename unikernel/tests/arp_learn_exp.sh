#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/arp_learn_exp.sh — how long does a freshly booted
#  machine take to answer the FIRST connection from an on-subnet peer
#  it has never heard of?
#
#  MANUAL. Not part of any suite and not run by CI, because it needs
#  root (a tap device), a Firecracker binary, and tcpdump. It is here
#  because it is the evidence behind `__learn_sender` in
#  stdlib/net/stack.nu, and a claim about microseconds on a wire should
#  be re-runnable by whoever doubts it.
#
#  Usage:
#      NURL_FIRECRACKER=/path/to/firecracker \
#      unikernel/tests/arp_learn_exp.sh [image.elf] [tag]
#
#  Every variable that could answer on the stack's behalf is removed:
#
#    no QEMU      — Firecracker boots the same PVH image, so the
#                   hypervisor is not part of what is being measured
#    no slirp     — a real tap; frames are frames
#    no DHCP      — `ip=` on the kernel command line (the guest does not
#                   run a DHCP client at all when it is told)
#    no guessing  — tcpdump on the tap timestamps the inbound SYN and
#                   the outbound SYN-ACK. Neither endpoint is asked.
#
#  Three addresses in one /24 on the tap: .1 is the host's primary
#  (the address Linux ARPs from), .2 is clientA, .3 is clientB, and the
#  guest is .10. clientA is cheap either way — Linux's own ARP request
#  for the guest teaches the guest who .2 is, which is RFC 826's
#  receive side and was already implemented. clientB is the question:
#  by then the host's neighbour entry is valid, so no second ARP goes
#  out, and the guest has never heard of .3.
#
#  Measured before `__learn_sender` (2026-08-27), across runs:
#      client .2   SYN -> SYN-ACK       0.9-1.0 ms
#      client .3   SYN -> SYN-ACK   858.0-999.6 ms
#  and on the wire the reason, which is not the one the number suggests:
#      0.029  IP   .3 > .10:8080  SYN
#      0.041  ARP  who-has .3 tell .10        <- the SYN-ACK's place
#      0.041  ARP  reply .3 is-at ...         <- resolved in 0.3 ms
#      0.897  IP   .10:8080 > .3  SYN-ACK     <- 856 ms of retransmit timer
#  After: 0.9-1.0 ms and 3.7-7.9 ms, and no ARP request for .3 at all.
# ============================================================
set -uo pipefail

# awk's %f and its arithmetic follow the locale: on a Finnish desktop
# the decimal separator is a comma, the subtraction below yields 0, and
# every measurement prints as 0.0 ms — a harness that reports a perfect
# result because it cannot do arithmetic. hypervisor_gate.sh carries the
# same scar for readelf. CI never sees it; the fix belongs here.
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FC="${NURL_FIRECRACKER:-firecracker}"
IMG="${1:-$ROOT/build/unikernel/k8sd.elf}"
tag="${2:-arp}"
OUT="${NURL_EXP_OUT:-$(mktemp -d)}"
TAP="${NURL_EXP_TAP:-nurl0}"
NET="${NURL_EXP_NET:-172.31.7}"
GUEST_MAC=02:00:00:00:77:10

command -v "$FC" >/dev/null 2>&1 || { echo "no firecracker (set NURL_FIRECRACKER)" >&2; exit 3; }
command -v tcpdump >/dev/null 2>&1 || { echo "no tcpdump" >&2; exit 3; }
[ -f "$IMG" ] || { echo "no image at $IMG" >&2; exit 2; }
[ -w /dev/kvm ] || { echo "no /dev/kvm — Firecracker does not emulate" >&2; exit 3; }
sudo -n true 2>/dev/null || { echo "needs sudo for the tap and tcpdump" >&2; exit 3; }

cleanup() {
    [ -n "${fcpid:-}" ] && kill "$fcpid" 2>/dev/null
    sudo ip link del "$TAP" 2>/dev/null
}
trap cleanup EXIT

sudo ip link del "$TAP" 2>/dev/null
sudo ip tuntap add dev "$TAP" mode tap user "$USER"
for a in 1 2 3; do sudo ip addr add "$NET.$a/24" dev "$TAP"; done
sudo ip link set "$TAP" up

# Under TCG the guest's rdtsc is the host's; under KVM the leaf answers
# and this is ignored. Firecracker is KVM-only, so this is belt and
# braces — and the wrong value here is what once made a four-second
# DHCP delay look like a working boot.
TSC=$(sed -n 's/^model name.*@ *\([0-9.]*\)GHz.*/\1/p' /proc/cpuinfo | head -1 |
      awk '{printf "%d", $1 * 1000000}')
[ -n "$TSC" ] || TSC=1000000

cat > "$OUT/fc.json" <<JSON
{
  "boot-source": {
    "kernel_image_path": "$IMG",
    "boot_args": "tsc_khz=$TSC wallclock=$(date +%s) ip=$NET.10/24 port=8080 pod=exp platform=unikernel"
  },
  "drives": [],
  "network-interfaces": [
    { "iface_id": "eth0", "host_dev_name": "$TAP", "guest_mac": "$GUEST_MAC" }
  ],
  "machine-config": { "vcpu_count": 1, "mem_size_mib": 256 }
}
JSON

sudo tcpdump -i "$TAP" -nn -tt -s 128 -w "$OUT/$tag.pcap" -U > "$OUT/tcpdump.log" 2>&1 &
for _ in $(seq 1 100); do grep -q "listening on" "$OUT/tcpdump.log" 2>/dev/null && break; sleep 0.05; done
grep -q "listening on" "$OUT/tcpdump.log" || { echo "tcpdump did not start:"; cat "$OUT/tcpdump.log"; exit 1; }

"$FC" --no-api --config-file "$OUT/fc.json" > "$OUT/$tag.console" 2>&1 &
fcpid=$!
for _ in $(seq 1 500); do grep -q 'serving on' "$OUT/$tag.console" 2>/dev/null && break; sleep 0.02; done
grep -q 'serving on' "$OUT/$tag.console" || { echo "guest never listened:"; cat "$OUT/$tag.console"; exit 1; }

for c in 2 3; do
    code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' --interface "$NET.$c" \
           "http://$NET.10:8080/healthz" 2>/dev/null)
    echo "client $NET.$c: http=$code"
done

sleep 2
# SIGINT, and to tcpdump itself rather than to the sudo that started
# it: a SIGTERM to the parent leaves the capture unflushed, and a run
# whose capture was never flushed looks exactly like a run in which
# nothing happened. That cost an hour once.
td=$(pgrep -f "tcpdump -i $TAP" | tail -1)
[ -n "$td" ] && sudo kill -INT "$td"
sleep 1
sudo chmod a+r "$OUT/$tag.pcap" 2>/dev/null

echo
echo "--- $OUT/$tag.pcap ---"
tcpdump -r "$OUT/$tag.pcap" -nn -tt -q 2>/dev/null |
awk -v net="$NET" '
    NR == 1 { t0 = $1 }
    { printf "%8.3f  %s\n", $1 - t0, substr($0, index($0, $2)) }
    $2 == "IP" {
        split($3, s, "."); split($5, d, ".")
        src = s[1]"."s[2]"."s[3]"."s[4]; sport = s[5]
        dst = d[1]"."d[2]"."d[3]"."d[4]; dport = d[5]
        sub(":", "", dport)
        if (dport == "8080" && !(src in syn)) syn[src] = $1
        if (sport == "8080" && (dst in syn) && !(dst in done)) {
            ans[dst] = ($1 - syn[dst]) * 1000; done[dst] = 1
        }
    }
    END {
        printf "\n"
        for (c in ans) printf "%16s: first SYN -> first packet back = %8.1f ms\n", c, ans[c]
    }
'
