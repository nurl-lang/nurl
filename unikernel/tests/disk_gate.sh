#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/disk_gate.sh — the guest has a disk, and what it
#  wrote there is still on it after the machine stopped.
#
#  WHAT IT PROVES, in the order the layers stack up:
#
#   1. The image built with `--disk` carries the block stack: virtio-blk
#      (unikernel/drivers/virtioblk.nu), FAT (stdlib/fs/) and the VFS
#      dispatch (unikernel/boot/vfs.c).
#   2. It mounts a volume THIS REPOSITORY DID NOT MAKE — the disk is
#      formatted by `mkfs.vfat`, so the layout under test is the
#      format's, not our reading of it.
#   3. It writes: a counter, a long name with two dots, a subdirectory,
#      a file bigger than the sector cache, and lists the root through
#      the guest's own getdents64.
#   4. It BOOTS AGAIN against the same disk and finds the previous
#      boot's files. A filesystem that only worked while the machine
#      that wrote it was still running would pass a one-boot test.
#   5. `fsck.vfat` calls the result clean, and a reader on the host that
#      shares no code with the guest reads the guest's files back. The
#      second half matters: fsck checks STRUCTURE, and a filesystem can
#      be structurally perfect with every file's contents in the wrong
#      cluster.
#
#  Skips (loudly, exit 0) when qemu-system-x86_64 or mkfs.vfat is
#  missing. Everything else is a failure.
#
#  Usage:  unikernel/tests/disk_gate.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QEMU="${NURL_QEMU:-qemu-system-x86_64}"

command -v "$QEMU" >/dev/null 2>&1 || { echo "SKIP disk: no $QEMU"; exit 0; }
command -v mkfs.vfat >/dev/null 2>&1 || { echo "SKIP disk: no mkfs.vfat"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP disk: no python3"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
IMG="$WORK/disk.elf"
DISK="$WORK/guest.img"
fails=0

note() { printf '     %s\n' "$*"; }
fail() { echo "  disk: $*"; fails=$((fails + 1)); }

# ── build ───────────────────────────────────────────────────────
if ! "$ROOT/unikernel/build_unikernel.sh" --disk "$ROOT/unikernel/demos/disk.nu" \
        -o "$IMG" --out-dir "$WORK" >"$WORK/build.log" 2>&1; then
    echo "  disk: build failed"
    sed 's/^/     /' "$WORK/build.log" | head -20
    exit 1
fi

# What the layer COSTS, measured on the same program built both ways —
# which is the only comparison that answers the question. `--disk` is
# opt-in precisely so a program with no disk keeps its old size, and a
# flag whose two settings produced the same image would be worth
# nothing. The control also proves the diskless build still links: every
# POSIX name the VFS took over has to resolve with the NURL side absent.
if ! "$ROOT/unikernel/build_unikernel.sh" "$ROOT/unikernel/demos/disk.nu" \
        -o "$WORK/nodisk.elf" --out-dir "$WORK/nodisk" >>"$WORK/build.log" 2>&1; then
    fail "control build (the same demo without --disk) failed"
else
    with=$(stat -c %s "$IMG")
    without=$(stat -c %s "$WORK/nodisk.elf")
    note "the same program: $with bytes with --disk, $without without (+$((with - without)))"
    [ "$with" -gt "$without" ] || fail "--disk did not change the image"
fi

# ── a volume mkfs.vfat made, not one we did ─────────────────────
dd if=/dev/zero of="$DISK" bs=1M count=32 status=none
mkfs.vfat -F 16 -n GUESTDISK "$DISK" >/dev/null 2>&1 || { fail "mkfs.vfat failed"; exit 1; }

boot_once() {
    "$ROOT/unikernel/run_qemu.sh" "$IMG" -t 90 -- \
        -drive file="$DISK",format=raw,if=none,id=d0 \
        -device virtio-blk-device,drive=d0 2>&1
}

# ── boot 1: an empty filesystem, written ────────────────────────
out1=$(boot_once)
case "$out1" in
    *"boots_before=0"*) ;;
    *) fail "first boot did not see an empty disk"; note "$(printf '%s' "$out1" | head -5)" ;;
esac
for want in "counter written: yes" "long name written: yes" "nested write: yes" \
            "big write: yes" "synced: yes"; do
    case "$out1" in
        *"$want"*) ;;
        *) fail "first boot: missing '$want'" ;;
    esac
done
case "$out1" in
    *"big size=8192"*) ;;
    *) fail "first boot: the big file is not 8192 bytes" ;;
esac
# Every name it made must come back out of readdir, including the long
# one — a filesystem that stored `data.lsm.wal` as `DATALS~1.WAL` and
# listed it that way would pass every other check here.
for want in "ent: boots.txt" "ent: data.lsm.wal" "ent: var" "ent: big.txt"; do
    case "$out1" in
        *"$want"*) ;;
        *) fail "first boot: readdir is missing '$want'" ;;
    esac
done

# ── boot 2 and 3: the previous boot's files are still there ─────
out2=$(boot_once)
case "$out2" in
    *"boots_before=1"*) ;;
    *) fail "second boot did not read the first boot's counter"; note "$(printf '%s' "$out2" | head -5)" ;;
esac
out3=$(boot_once)
case "$out3" in
    *"boots_before=2"*) ;;
    *) fail "third boot did not read the second boot's counter" ;;
esac
case "$out3" in
    *"long name reads=ok"*) ;;
    *) fail "the long-named file did not read back after two reboots" ;;
esac

# ── the host's own opinion of what the guest wrote ──────────────
if command -v fsck.vfat >/dev/null 2>&1; then
    if fsck_out=$(fsck.vfat -n "$DISK" 2>&1); then
        note "fsck.vfat: $(printf '%s' "$fsck_out" | tail -1)"
    else
        fail "fsck.vfat calls the guest's filesystem corrupt"
        printf '%s\n' "$fsck_out" | head -10 | sed 's/^/     /'
    fi
else
    note "fsck.vfat absent — structure unchecked"
fi

# A reader that shares NO code with the guest. fsck checks that the
# structure is consistent; this checks that the BYTES are where the
# directory says they are, which is a different question and the one a
# cluster-arithmetic bug gets wrong.
py_out=$(python3 "$ROOT/unikernel/tests/fatread.py" "$DISK" /boots.txt /data.lsm.wal /var/state.json 2>&1)
py_rc=$?
if [ $py_rc -ne 0 ]; then
    fail "the independent FAT reader could not read the guest's disk"
    printf '%s\n' "$py_out" | head -10 | sed 's/^/     /'
else
    case "$py_out" in
        *"/boots.txt=3"*) ;;
        *) fail "the counter on the medium is not 3"; note "$py_out" ;;
    esac
    case "$py_out" in
        *"/data.lsm.wal=record-0001"*) ;;
        *) fail "the long-named file's contents are wrong on the medium"; note "$py_out" ;;
    esac
    case "$py_out" in
        *'/var/state.json={"up":true}'*) ;;
        *) fail "the nested file's contents are wrong on the medium"; note "$py_out" ;;
    esac
    note "read back on the host by an independent reader: $(printf '%s' "$py_out" | tr '\n' ' ')"
fi

# ── a blank disk the guest formats itself ───────────────────────
# The other half of "a machine with a disk is self-sufficient": no host
# ran `mkfs` on this one. `disk=format` formats only what does not
# mount, so the SECOND boot must find the first boot's counter rather
# than a fresh filesystem — a format-on-every-boot would pass a
# single-boot test and lose the data of every real one.
BLANK="$WORK/blank.img"
dd if=/dev/zero of="$BLANK" bs=1M count=48 status=none
fmt1=$(NURL_APPEND='disk=format' "$ROOT/unikernel/run_qemu.sh" "$IMG" -t 90 -- \
        -drive file="$BLANK",format=raw,if=none,id=d0 \
        -device virtio-blk-device,drive=d0 2>&1)
case "$fmt1" in
    *"boots_before=0"*"counter written: yes"*) ;;
    *) fail "the guest could not format a blank disk"; note "$(printf '%s' "$fmt1" | head -5)" ;;
esac
fmt2=$(NURL_APPEND='disk=format' "$ROOT/unikernel/run_qemu.sh" "$IMG" -t 90 -- \
        -drive file="$BLANK",format=raw,if=none,id=d0 \
        -device virtio-blk-device,drive=d0 2>&1)
case "$fmt2" in
    *"boots_before=1"*) ;;
    *) fail "disk=format reformatted a filesystem that mounted"; note "$(printf '%s' "$fmt2" | head -5)" ;;
esac
if command -v fsck.vfat >/dev/null 2>&1; then
    if ! fsck.vfat -n "$BLANK" >"$WORK/fsck2.log" 2>&1; then
        fail "fsck.vfat calls the guest-FORMATTED filesystem corrupt"
        head -10 "$WORK/fsck2.log" | sed 's/^/     /'
    else
        note "guest-formatted volume: $(tail -1 "$WORK/fsck2.log")"
    fi
fi

# ── a disk the guest was told to ignore ─────────────────────────
# `disk=off` must produce the same machine as no disk at all. Without
# this the flag is untested and "the guest ignores the disk" is a claim
# rather than a behaviour.
off=$(NURL_APPEND='disk=off' "$ROOT/unikernel/run_qemu.sh" "$IMG" -t 90 -- \
        -drive file="$DISK",format=raw,if=none,id=d0 \
        -device virtio-blk-device,drive=d0 2>&1)
case "$off" in
    *"counter written: no"*) ;;
    *) fail "disk=off still wrote to the disk"; note "$(printf '%s' "$off" | head -5)" ;;
esac

if [ "$fails" -eq 0 ]; then
    echo "  disk: a mkfs.vfat volume mounted, written across three boots, and read back by fsck.vfat and an independent reader"
    exit 0
fi
exit 1
