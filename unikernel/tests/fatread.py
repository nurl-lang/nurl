#!/usr/bin/env python3
"""Read files out of a FAT12/16/32 image. An oracle, not a tool.

unikernel/tests/disk_gate.sh uses this to check what the GUEST wrote to
a disk. `fsck.vfat` already answers "is the structure consistent"; this
answers the different question "are the bytes where the directory says
they are", which a cluster-arithmetic bug gets wrong while leaving a
structurally perfect filesystem behind.

It shares no code with stdlib/fs/fat.nu on purpose — an implementation
checking its own work proves only that it is self-consistent. Written
from the format, in a different language, by a different reading of the
spec.

Usage:  fatread.py <image> <path> [<path> ...]
Prints  <path>=<contents> per line; exits non-zero on any failure.
"""

import struct
import sys

SECTOR = 512
ATTR_LFN = 0x0F
ATTR_VOLID = 0x08
ATTR_DIR = 0x10


class Fat:
    def __init__(self, data):
        self.d = data
        b = data[:SECTOR]
        self.bps = struct.unpack("<H", b[11:13])[0]
        self.spc = b[13]
        self.rsvd = struct.unpack("<H", b[14:16])[0]
        self.nfats = b[16]
        self.root_ents = struct.unpack("<H", b[17:19])[0]
        tot16 = struct.unpack("<H", b[19:21])[0]
        spf16 = struct.unpack("<H", b[22:24])[0]
        tot32 = struct.unpack("<I", b[32:36])[0]
        spf32 = struct.unpack("<I", b[36:40])[0]
        self.root_clus = struct.unpack("<I", b[44:48])[0]
        if self.bps != SECTOR:
            raise SystemExit("fatread: %d-byte sectors are not supported" % self.bps)
        self.fat_secs = spf16 or spf32
        self.total = tot16 or tot32
        self.root_secs = (self.root_ents * 32 + SECTOR - 1) // SECTOR
        self.fat_start = self.rsvd
        self.root_start = self.rsvd + self.nfats * self.fat_secs
        self.data_start = self.root_start + self.root_secs
        self.nclus = (self.total - self.data_start) // self.spc
        self.type = 12 if self.nclus < 4085 else (16 if self.nclus < 65525 else 32)

    def sector(self, lba):
        off = lba * SECTOR
        return self.d[off:off + SECTOR]

    def fat_entry(self, c):
        if self.type == 32:
            off = self.fat_start * SECTOR + c * 4
            return struct.unpack("<I", self.d[off:off + 4])[0] & 0x0FFFFFFF
        if self.type == 16:
            off = self.fat_start * SECTOR + c * 2
            return struct.unpack("<H", self.d[off:off + 2])[0]
        off = self.fat_start * SECTOR + c + c // 2
        raw = self.d[off] | (self.d[off + 1] << 8)
        return (raw & 0x0FFF) if c % 2 == 0 else (raw >> 4)

    def eoc(self, e):
        return e >= {12: 0xFF8, 16: 0xFFF8, 32: 0x0FFFFFF8}[self.type]

    def chain(self, first):
        out, c, guard = [], first, 0
        while 2 <= c <= self.nclus + 1 and guard <= self.nclus + 2:
            out.append(c)
            e = self.fat_entry(c)
            if self.eoc(e) or e == 0:
                break
            c = e
            guard += 1
        return out

    def clus_bytes(self, c):
        lba = self.data_start + (c - 2) * self.spc
        off = lba * SECTOR
        return self.d[off:off + self.spc * SECTOR]

    def dir_entries(self, dirclus):
        """Yield (name, attr, first_cluster, size) for one directory."""
        if dirclus == 0 and self.type != 32:
            off = self.root_start * SECTOR
            raw = self.d[off:off + self.root_secs * SECTOR]
        else:
            raw = b"".join(self.clus_bytes(c) for c in self.chain(dirclus))

        lfn = {}
        lfn_sum = None
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if len(e) < 32 or e[0] == 0:
                break
            if e[0] == 0xE5:
                lfn, lfn_sum = {}, None
                continue
            attr = e[11]
            if attr & 0x3F == ATTR_LFN:
                order = e[0] & 0x3F
                if e[0] & 0x40:
                    lfn, lfn_sum = {}, e[13]
                if lfn_sum is not None and e[13] == lfn_sum:
                    chars = e[1:11] + e[14:26] + e[28:32]
                    lfn[order] = chars
                continue
            if attr & ATTR_VOLID and not (attr & ATTR_DIR):
                lfn, lfn_sum = {}, None
                continue

            name = None
            if lfn and lfn_sum == sfn_checksum(e[:11]):
                buf = b""
                for k in sorted(lfn):
                    buf += lfn[k]
                text = ""
                for j in range(0, len(buf), 2):
                    ch = buf[j] | (buf[j + 1] << 8)
                    if ch in (0x0000, 0xFFFF):
                        break
                    text += chr(ch)
                name = text
            if name is None:
                base = e[:8].decode("latin-1").rstrip(" ")
                ext = e[8:11].decode("latin-1").rstrip(" ")
                if e[12] & 0x08:
                    base = base.lower()
                if e[12] & 0x10:
                    ext = ext.lower()
                name = base + ("." + ext if ext else "")
            first = (struct.unpack("<H", e[20:22])[0] << 16) | struct.unpack("<H", e[26:28])[0]
            size = struct.unpack("<I", e[28:32])[0]
            yield name, attr, first, size
            lfn, lfn_sum = {}, None

    def lookup(self, path):
        parts = [p for p in path.split("/") if p]
        cur = self.root_clus if self.type == 32 else 0
        for k, part in enumerate(parts):
            hit = None
            for name, attr, first, size in self.dir_entries(cur):
                if name.lower() == part.lower():
                    hit = (attr, first, size)
                    break
            if hit is None:
                raise KeyError(path)
            attr, first, size = hit
            if k == len(parts) - 1:
                return attr, first, size
            if not attr & ATTR_DIR:
                raise KeyError(path)
            cur = first if first else (self.root_clus if self.type == 32 else 0)
        raise KeyError(path)

    def read(self, path):
        attr, first, size = self.lookup(path)
        if attr & ATTR_DIR:
            raise KeyError(path + " is a directory")
        out = b"".join(self.clus_bytes(c) for c in self.chain(first)) if first else b""
        return out[:size]


def sfn_checksum(name11):
    s = 0
    for b in name11:
        s = (((s >> 1) | ((s & 1) << 7)) + b) & 0xFF
    return s


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(argv[1], "rb") as fh:
        fs = Fat(fh.read())
    rc = 0
    for path in argv[2:]:
        try:
            data = fs.read(path)
        except KeyError as exc:
            print("%s=<MISSING: %s>" % (path, exc))
            rc = 1
            continue
        print("%s=%s" % (path, data.decode("utf-8", "replace").strip()))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
