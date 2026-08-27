#!/bin/sh
# unikernel/k8s/entrypoint.sh — the container's only job is to point a
# CPU at the image and forward a port.
#
# Nothing here is Kubernetes-specific: the same command runs the image
# on a laptop. What Kubernetes contributes is the environment —
# POD_NAME from the downward API, PORT from the container spec — and
# those become kernel command line keys, which `cmdenv.c` presents to
# the guest as its environment.
set -eu

IMAGE="${IMAGE:-/srv/server.elf}"
PORT="${PORT:-8080}"
GUEST_PORT="${GUEST_PORT:-8080}"
MEM="${MEM:-256}"
POD="${POD_NAME:-$(hostname)}"

# KVM when the node gave us the device, TCG when it did not. The
# difference is speed and the clock, not behaviour: this image boots to
# a served request in under two seconds either way.
if [ -w /dev/kvm ]; then
    ACCEL=kvm
else
    ACCEL=tcg
fi

# The TSC frequency, which the guest refuses to invent.
#
# Under KVM the guest reads it from CPUID leaf 0x40000010 and ignores
# what we say here. Under TCG QEMU's rdtsc IS the host's rdtsc, so the
# honest value is the host's nominal TSC frequency — not QEMU's
# documented 1 GHz, which would make the guest's clock run at whatever
# ratio the host's TSC happens to have to it. Sources, best first:
# the kernel's own figure, then Intel's nominal frequency out of the
# model name, then the current (boost/idle-dependent) core frequency.
tsc_khz() {
    if [ -r /sys/devices/system/cpu/cpu0/tsc_freq_khz ]; then
        cat /sys/devices/system/cpu/cpu0/tsc_freq_khz
        return
    fi
    ghz=$(sed -n 's/^model name.*@ *\([0-9.]*\)GHz.*/\1/p' /proc/cpuinfo | head -1)
    if [ -n "$ghz" ]; then
        awk -v g="$ghz" 'BEGIN { printf "%d\n", g * 1000000 }'
        return
    fi
    mhz=$(sed -n 's/^cpu MHz[^0-9]*\([0-9.]*\).*/\1/p' /proc/cpuinfo | head -1)
    if [ -n "$mhz" ]; then
        echo "entrypoint: no nominal TSC frequency; using the current core frequency" >&2
        awk -v m="$mhz" 'BEGIN { printf "%d\n", m * 1000 }'
        return
    fi
    echo "entrypoint: no TSC frequency anywhere; the guest clock will be wrong" >&2
    echo 1000000
}

# `platform` is the launcher telling the guest what is underneath it.
# The program cannot find that out, and a program that asserts it
# anyway is one whose banner stops being checkable the day the same
# source is built the other way — which it now is.
APPEND="tsc_khz=$(tsc_khz) wallclock=$(date +%s) pod=${POD} port=${GUEST_PORT} platform=unikernel"
echo "entrypoint: accel=${ACCEL} append=[${APPEND}] forwarding :${PORT} -> guest:${GUEST_PORT}" >&2

# exec, so QEMU is PID 1 and Kubernetes' SIGTERM reaches the hypervisor
# rather than a shell that would outlive it.
exec qemu-system-x86_64 \
    -M microvm,acpi=off,rtc=off \
    -accel "${ACCEL}" -cpu max -m "${MEM}" \
    -nodefaults -no-reboot -no-user-config \
    -global virtio-mmio.force-legacy=false \
    -kernel "${IMAGE}" \
    -append "${APPEND}" \
    -device virtio-net-device,netdev=n0 \
    -netdev "user,id=n0,hostfwd=tcp::${PORT}-:${GUEST_PORT}" \
    -serial stdio -display none
