#!/usr/bin/env python3
# tools/fuzz/fuzz_parsers.py — mutational + grammar-based fuzzer for the
# untrusted-input parsers: the data formats (x509/DER, cbor, msgpack, json,
# yaml, xml, toml) and the network-facing protocol parsers (HTTP/1.1
# server and client, HTTP/2 frames + HPACK, HTTP/3 frames + QPACK, TLS
# record layer + ClientHello / ServerHello, WebSocket frames incl.
# permessage-deflate, MQTT packets, multipart, URL / query / cookie).
#
# Inputs come from three places, mixed per target:
#     * static seeds below (valid + deliberately adversarial),
#     * on-disk captures under tools/fuzz/corpus/<target>/ (real TLS hellos
#       from OpenSSL, Python and the NURL client; a real server flight),
#     * a per-protocol generator that builds a structurally valid message
#       stream (lengths, varints, frame headers all consistent) with random
#       field values — so mutations reach the parser's semantic checks
#       instead of dying at the first length field.
# Every input then goes through 0–6 byte-level mutations.
#
# It runs the ASan+UBSan-built harness (tools/fuzz/parse_harness.nu) on
# batches of inputs. A parser must ALWAYS finish with either a value or a
# graceful error — never a crash, out-of-bounds access, UB, unbounded
# allocation or a hang. So a finding is any of:
#     * non-zero / signal exit from the harness (abort, SIGSEGV, SIGFPE, …)
#     * an AddressSanitizer / UndefinedBehaviorSanitizer report on stderr,
#       including ASan refusing one allocation over --max-alloc-mb (an
#       attacker-chosen length reaching the allocator)
#     * RSS over --rss-mb (unbounded memory growth)
#     * a timeout (a hang or unbounded recursion the OS hasn't killed yet)
# A failing batch is re-run one input at a time to name the input; if no
# single input reproduces, the whole batch is saved (state carried across
# connections — e.g. a TLS ticket key or a shared table — is the suspect).
#
# Deterministic per --seed and target, so a finding reproduces. Failing
# inputs are saved under tools/fuzz/failures/ for triage.
#
# Usage:
#   fuzz_parsers.py --harness <bin> [--seed N] [--iters N] [--timeout SEC]
#                   [--formats a,b,...] [--minutes M] [--jobs J]
#                   [--summary out.json]
#   --iters N    N inputs in total, targets drawn at random (the classic mode)
#   --minutes M  instead: M minutes PER TARGET (time-budgeted campaign);
#                --jobs J targets run side by side

import argparse
import json
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAILDIR = os.path.join(ROOT, "tools", "fuzz", "failures")
CORPUS = os.path.join(ROOT, "tools", "fuzz", "corpus")

# ── Seed corpora (valid + deliberately adversarial) ──────────────────
TEXT_SEEDS = {
    "json": [
        b'{"a":1,"b":[1,2,3],"c":{"d":true,"e":null},"f":"str\\u00e9"}',
        b'[[[[[[[[[[1]]]]]]]]]]',
        b'{"x":  -1.5e10 , "y": 0.0}',
        b'"\\ud834\\udd1e"',            # surrogate pair
        b'[' + b'1,' * 500 + b'1]',
        b'{',                            # truncated
        b'[' * 4000,                     # deep-nesting DoS probe
    ],
    "yaml": [
        b"a: 1\nb:\n  - x\n  - y\nc: {k: v, l: [1, 2]}\n",
        b"- - - - - - - - - x\n",
        b"key: 'quoted '' value'\nflow: [a, {b: c}, d]\n",
        b"[" * 4000,                      # flow-nesting DoS probe
        b"deep:\n" + b" " * 0 + b"x: 1\n",
    ],
    "xml": [
        b'<?xml version="1.0"?><r a="1"><c>t</c><c2/></r>',
        b"<a>&lt;&amp;&#233;&#x1F600;</a>",
        b"<a><b><c><d>x</d></c></b></a>",
        b"<a>" * 4000,                    # element-nesting DoS probe
        b"<!-- unterminated",
        b"<a><![CDATA[ ]]]]></a>",
    ],
    "toml": [
        b'k = 1\nf = 1.5\ns = "str"\n[t]\nx = "y"\n[[arr]]\nn = 1\n',
        b'a = [1, [2, [3, [4]]]]\n',
        b'd = 2020-01-01T00:00:00Z\n',
        b'k = ' + b'[' * 2000,
    ],
    "urlish": [
        b"https://user:pw@example.com:8443/a/b%20c?x=1&y=%41%zz&z#frag",
        b"http://[::1]:80/?a=b+c&&=&k",
        b"/p?q=%e2%82%ac&e=%",
        b"sid=abc; Domain=.example.com; Path=/a; Max-Age=3600; Secure; HttpOnly; SameSite=Lax",
        b"x=y; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Domain=example.com",
        b"permessage-deflate; client_max_window_bits=10; server_no_context_takeover",
        b"permessage-deflate; server_max_window_bits",
        b"%" * 300 + b"=" + b"&" * 300,
    ],
    "pem": [
        b"-----BEGIN CERTIFICATE-----\nMAA=\n-----END CERTIFICATE-----\n",
        b"-----BEGIN CERTIFICATE REQUEST-----\n" + b"A" * 3000 + b"\n-----END CERTIFICATE REQUEST-----\n",
        b"-----BEGIN X-----\n====\n",
    ],
}

BINARY_SEEDS = {
    # A DER SEQUENCE with a couple of INTEGERs — the shape x509_parse walks.
    "x509": [
        bytes.fromhex("3006020101020102"),
        bytes.fromhex("30820006"),                 # long-form length, no body
        bytes.fromhex("3080020100"),               # indefinite-length (invalid in DER)
        bytes.fromhex("30ff"),                      # length byte lies (0xff bytes follow)
        bytes.fromhex("30840fffffff020101"),        # 4-byte length claiming ~256MB
        b"\x30" * 200,                              # nested-SEQUENCE probe
    ],
    "cbor": [
        bytes.fromhex("a161610161620263"),          # {"a":1,"b":2}
        bytes.fromhex("9f01029f0304ffff"),          # indefinite arrays
        bytes.fromhex("5bffffffffffffffff"),        # byte string, 2^64-1 length
        bytes.fromhex("bf6161016162ff"),            # indefinite map
        b"\x9f" * 300,                              # indefinite-array nesting probe
    ],
    "msgpack": [
        bytes.fromhex("82a1610181a1620263"),        # {"a":[1],"b":2}
        bytes.fromhex("dd ffffffff".replace(" ", "")),  # array32, 2^32-1 elements
        bytes.fromhex("c4ffffffffff"),              # bin8-ish with big length
        b"\x91" * 300,                              # fixarray nesting probe
    ],
    # byte 0 = dynamic-table size selector; RFC 7541 Appendix C blocks.
    "hpack": [
        b"\x20" + bytes.fromhex("400a637573746f6d2d6b65790d637573746f6d2d686561646572"),
        b"\x20" + bytes.fromhex("828684418cf1e3c2e5f23a6ba0ab90f4ff"),
        b"\x20" + bytes.fromhex("828684be5886a8eb10649cbf"),
        b"\x01" + bytes.fromhex("488264025885aec3771a4b6196d07abe941054d444a8200595040b8166e082a62d1bff"),
        b"\x00" + bytes.fromhex("3fe11f"),                    # size update to 4096 over a 0 cap
        b"\x20" + b"\xff" + b"\xff" * 10 + b"\x7f",           # overlong integer
        b"\x20" + b"\x40\x7f" + b"\xff" * 8,                  # literal name length 2^56-ish
    ],
    "h2frame": [
        bytes.fromhex("000006040000000000000300000064"),          # SETTINGS
        bytes.fromhex("0000080600000000000102030405060708"),      # PING
        bytes.fromhex("00000a0009000000010548656c6c6f0000000000"),  # DATA padded
        bytes.fromhex("0000010008000000010a"),                    # DATA pad > len
    ],
    "qpack": [
        bytes.fromhex("0000d1d75f1d0f2f"),          # :method GET, :path /, …
        bytes.fromhex("00005f0a04746573742a0161"),
        bytes.fromhex("0000ffffffffffffffffff7f"),  # overlong static index
        bytes.fromhex("3fe11f"),                    # encoder: set capacity 4096
    ],
    "h3frame": [
        bytes.fromhex("0406010006804000000703"),
        bytes.fromhex("0108000000d1d75f1d") + bytes.fromhex("0003616263"),
        bytes.fromhex("21000400060000"),
    ],
    "multipart": [
        b"XyZ\n--XyZ\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nhello\r\n"
        b"--XyZ\r\nContent-Disposition: form-data; name=\"file\"; filename=\"f.txt\"\r\n"
        b"Content-Type: text/plain\r\n\r\nline1\r\nline2\r\n--XyZ--\r\n",
        b"b\n--b\r\n\r\n\r\n--b--",
        b"b\n--b\r\nContent-Disposition: form-data; name=\"" + b"x" * 500,
    ],
    "http1": [
        b"GET / HTTP/1.1\r\nHost: x\r\n\r\n",
        b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\nT: v\r\n\r\n",
        b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhelloGET /b HTTP/1.1\r\nHost: x\r\n\r\n",
        b"POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
        b"POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFFFFFFF\r\n",
        b"GET /p?a=%41&b=c HTTP/1.0\r\nHost: x\r\nConnection: keep-alive\r\nX: a\r\n b\r\n\r\n",
    ],
    "http1resp": [
        b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n",
        b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 204 No Content\r\n\r\n",
        b"HTTP/1.0 200 OK\r\nConnection: close\r\n\r\nbody to eof",
        b"HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/\r\nContent-Length: 0\r\n\r\n",
    ],
    "mqtt": [
        bytes.fromhex("3011000474657374") + b"hello" + bytes.fromhex("0000000000")[:0],
        bytes.fromhex("d000"),                                   # PINGRESP
        bytes.fromhex("3280808001"),                             # remaining length 2^21 + no body
        bytes.fromhex("3014000161000108260001610001620161626364"),
        bytes.fromhex("e000"),                                   # DISCONNECT
    ],
    "ws": [
        b"\x00\x81\x85\x01\x02\x03\x04" + bytes(a ^ b for a, b in zip(b"hello", b"\x01\x02\x03\x04\x01")),
        b"\x02\x81\x05hello",
        b"\x00\x88\x82\x00\x00\x00\x00\x03\xe8",
        b"\x00\x01\x83\x00\x00\x00\x00abc\x80\x83\x00\x00\x00\x00def",
        b"\x00\x82\xff\x00\x00\x00\x00\xff\xff\xff\xff\x00\x00\x00\x00",  # 64-bit length
    ],
    "h2": [
        b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + bytes.fromhex("000000040000000000")
        + bytes.fromhex("000005010500000001") + bytes.fromhex("8286841f") + b"\x00",
    ],
    "tls": [],
    "tlscli": [],
    "csr": [b"\x30\x82\x01\x00\x30\x00", b"\x30" * 100],
    "tlscert": [b"\x00\x0b\x00\x00\x09\x00\x00\x00\x05\x00\x00\x01\x00",
                b"\x01\x0b\x00\x00\x06\x00\x00\x03\xff\xff\xff"],
}

# Real captures live on disk: TLS hellos / a server flight (corpus/tls),
# certificates and CSRs minted by OpenSSL (corpus/x509). (directory,
# file-name prefix) per target.
CORPUS_DIRS = {"tls": [("tls", "ch_")], "tlscli": [("tls", "sh_")],
               "x509": [("x509", "cert_")], "csr": [("x509", "csr_")]}


def load_corpus(fmt):
    out = []
    for d, prefix in CORPUS_DIRS.get(fmt, [(fmt, "")]):
        p = os.path.join(CORPUS, d)
        if not os.path.isdir(p):
            continue
        for name in sorted(os.listdir(p)):
            if name.startswith(prefix):
                with open(os.path.join(p, name), "rb") as fh:
                    out.append(fh.read())
    return out


# ── encoders shared by the generators ────────────────────────────────

def u8(v): return bytes([v & 0xFF])
def u16(v): return struct.pack(">H", v & 0xFFFF)
def u24(v): return struct.pack(">I", v & 0xFFFFFF)[1:]
def u32(v): return struct.pack(">I", v & 0xFFFFFFFF)


def pick_len(rng, actual):
    """Mostly the honest length; sometimes a lie."""
    if rng.random() > ODD / 3:
        return actual
    return max(0, rng.choice([0, 1, actual - 1, actual + 1, actual * 2, 0xFFFF, 0xFFFFFF, rng.randint(0, 70000)]))


def hpack_int(rng, value, prefix, flags):
    """RFC 7541 §5.1 integer, occasionally over-long (redundant 0x80s)."""
    mx = (1 << prefix) - 1
    if value < mx:
        return bytes([flags | value])
    out = bytearray([flags | mx])
    value -= mx
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    if rng.random() < ODD / 3:
        out += b"\x80" * rng.randint(1, 12)
    out.append(value)
    return bytes(out)


HUFF = [bytes.fromhex(h) for h in ("f1e3c2e5f23a6ba0ab90f4ff", "a8eb10649cbf",
                                   "25a849e95ba97d7f", "25a849e95bb8e8b4bf",
                                   "6402", "aec3771a4b", "d07abe941054d444a8200595040b8166e082a62d1bff")]
H2_NAMES = [b":method", b":path", b":scheme", b":authority", b":status", b"content-length",
            b"transfer-encoding", b"connection", b"te", b"cookie", b"host", b"x-a", b"",
            b"Upper", b"bad\x00name", b"content-type"]
H2_VALUES = [b"GET", b"POST", b"/", b"/a?b=c", b"http", b"https", b"localhost", b"5", b"-1",
             b"trailers", b"chunked", b"", b"a\r\nb", b"x" * 300, b"99999999999999999999"]


def hpack_string(rng, s):
    if rng.random() < 0.25:
        body = rng.choice(HUFF) if rng.random() > ODD else rng.randbytes(rng.randint(0, 12))
        return hpack_int(rng, pick_len(rng, len(body)), 7, 0x80) + body
    return hpack_int(rng, pick_len(rng, len(s)), 7, 0) + s


def gen_hpack_block(rng, request=False):
    out = bytearray()
    if rng.random() < 0.15:
        out += hpack_int(rng, rng.choice([0, 64, 4096, 1 << 20, rng.randint(0, 9000)]), 5, 0x20)
    if request:
        out += b"\x82" if rng.random() < 0.8 else b"\x83"      # :method GET / POST
        out += b"\x86"                                          # :scheme http
        out += b"\x84" if rng.random() < 0.7 else b"\x44" + hpack_string(rng, b"/a?b=c")  # :path
        out += b"\x41" + hpack_string(rng, b"localhost")        # :authority
    for _ in range(odd(rng, [0, 1, 2, 3], [5, 8, 40])):
        if rng.random() > ODD:                                  # a well-formed regular field
            r = rng.random()
            if r < 0.3:
                out += hpack_int(rng, rng.randint(15, 61), 7, 0x80)
            else:
                flags, prefix = rng.choice([(0x40, 6), (0x00, 4), (0x10, 4)])
                out += hpack_int(rng, rng.choice([16, 19, 28, 31, 32, 58]), prefix, flags)
                out += hpack_string(rng, rng.choice([b"*/*", b"gzip", b"a=b", b"text/plain", b"nurl/1"]))
            continue
        r = rng.random()
        if r < 0.3:                                             # indexed, odd index
            out += hpack_int(rng, rng.choice([0, 1, 2, 4, 8, 61, 62, 63, 70, rng.randint(0, 200)]), 7, 0x80)
        elif r < 0.85:                                          # literal forms, odd names / values
            flags, prefix = rng.choice([(0x40, 6), (0x00, 4), (0x10, 4)])
            if rng.random() < 0.5:
                out += hpack_int(rng, rng.randint(1, 70), prefix, flags)
            else:
                out += hpack_int(rng, 0, prefix, flags) + hpack_string(rng, rng.choice(H2_NAMES))
            out += hpack_string(rng, rng.choice(H2_VALUES))
        else:                                                   # size update (late: illegal)
            out += hpack_int(rng, rng.randint(0, 5000), 5, 0x20)
    return bytes(out)


def gen_hpack(rng):
    return u8(rng.randint(0, 255)) + gen_hpack_block(rng, rng.random() < 0.5)


H2_PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"


def h2_frame(rng, ftype, flags, sid, payload):
    return u24(pick_len(rng, len(payload))) + u8(ftype) + u8(flags) + u32(sid) + payload


def gen_h2_frames(rng, n):
    out = bytearray()
    sid = -1
    for _ in range(n):
        r = rng.random()
        if r < 0.3 or sid < 0:                                  # HEADERS (+CONTINUATION)
            sid += 2
            s = sid if rng.random() > ODD else rng.choice([0, 2, max(sid - 2, 0), 0x7FFFFFFF, 0xFFFFFFFF])
            blk = gen_hpack_block(rng, True)
            flags = odd(rng, [0x5, 0x5, 0x4], [0x1, 0x0, 0x25, 0x2d, 0x0c, 0x24])
            pre = b""
            if flags & 0x8:
                pre += u8(rng.randint(0, 20))
            if flags & 0x20:
                pre += u32(rng.choice([0, s, 0x80000000 | s])) + u8(rng.randint(0, 255))
            post = b"\x00" * (pre[0] if flags & 0x8 and pre and rng.random() < 0.7 else 0)
            if rng.random() < 0.25:                             # split across CONTINUATION
                cuts = sorted(rng.randint(0, len(blk)) for _ in range(rng.randint(1, 3)))
                pieces = [blk[a:b] for a, b in zip([0] + cuts, cuts + [len(blk)])]
                out += h2_frame(rng, 1, flags & ~0x4, s, pre + pieces[0] + post)
                for k, piece in enumerate(pieces[1:]):
                    last = k == len(pieces) - 2
                    out += h2_frame(rng, 9, 4 if last or rng.random() < ODD else 0, s, piece)
            else:
                out += h2_frame(rng, 1, flags, s, pre + blk + post)
            continue
        s = sid if rng.random() > ODD else rng.choice([0, 2, sid + 2, 0x7FFFFFFF, 0xFFFFFFFF])
        if r < 0.5:                                             # DATA
            body = rng.randbytes(rng.randint(0, 64))
            flags = odd(rng, [0, 1], [8, 9])
            if flags & 8:
                pad = rng.randint(0, 300)
                body = u8(pad) + body + b"\x00" * min(pad, 40)
            out += h2_frame(rng, 0, flags, s, body)
        elif r < 0.6:                                           # SETTINGS
            p = b"".join(u16(odd(rng, [1, 3, 4, 5, 6], [2, 8, 9, rng.randint(0, 0xFFFF)])) +
                         u32(odd(rng, [0, 100, 4096, 16384, 65535], [1, 16777215, 0x7FFFFFFF, 0xFFFFFFFF, rng.randint(0, 1 << 32)]))
                         for _ in range(rng.randint(0, 5)))
            out += h2_frame(rng, 4, odd(rng, [0, 1], [3]), odd(rng, [0], [1]), p)
        elif r < 0.7:                                           # WINDOW_UPDATE
            out += h2_frame(rng, 8, 0, rng.choice([0, s]), u32(odd(rng, [1, 65535, 1 << 20], [0, 0x7FFFFFFF, 0xFFFFFFFF])))
        elif r < 0.77:
            out += h2_frame(rng, 6, rng.choice([0, 1]), odd(rng, [0], [1]), rng.randbytes(odd(rng, [8], [0, 7, 9])))
        elif r < 0.82:
            out += h2_frame(rng, 3, 0, s, u32(rng.randint(0, 14)))
        elif r < 0.87:
            out += h2_frame(rng, 2, 0, s, u32(rng.randint(0, sid + 2)) + u8(rng.randint(0, 255)))
        elif r < 0.9:
            out += h2_frame(rng, 7, 0, 0, u32(rng.randint(0, sid)) + u32(rng.randint(0, 14)) + rng.randbytes(rng.randint(0, 9)))
        elif r < 0.93:
            out += h2_frame(rng, 5, 4, s, u32(s + 1) + gen_hpack_block(rng, True))
        elif r < 0.96:
            out += h2_frame(rng, 9, rng.choice([0, 4]), s, gen_hpack_block(rng))
        else:
            out += h2_frame(rng, rng.randint(10, 255), rng.randint(0, 255), s, rng.randbytes(rng.randint(0, 20)))
    return bytes(out)


def gen_h2frame(rng):
    return gen_h2_frames(rng, rng.randint(1, 8))


def gen_h2(rng):
    pre = H2_PREFACE
    if rng.random() < 0.9:
        pre += h2_frame(rng, 4, 0, 0, b"")
    return pre + gen_h2_frames(rng, rng.randint(1, 14))


def qvarint(rng, v):
    """QUIC varint (RFC 9000 §16), sometimes non-minimal."""
    if v < 64 and rng.random() > 0.1:
        return u8(v)
    if v < 16384 and rng.random() > 0.1:
        return u16(0x4000 | v)
    if v < (1 << 30) and rng.random() > 0.1:
        return u32(0x80000000 | v)
    return struct.pack(">Q", (0xC0 << 56) | (v & ((1 << 62) - 1)))


def qpack_str(rng, s, prefix, flags):
    if rng.random() < 0.2:
        body = rng.choice(HUFF)
        return hpack_int(rng, pick_len(rng, len(body)), prefix, flags | (1 << prefix)) + body
    return hpack_int(rng, pick_len(rng, len(s)), prefix, flags) + s


def gen_qpack_section(rng):
    out = bytearray()
    out += hpack_int(rng, rng.choice([0, 0, 0, 1, 2, rng.randint(0, 300)]), 8, 0)
    out += hpack_int(rng, rng.choice([0, 0, 0, 1, rng.randint(0, 300)]), 7, rng.choice([0, 0x80]))
    for _ in range(rng.randint(0, 8)):
        r = rng.random()
        if r < 0.4:     # indexed field line, static (T=1) or dynamic
            out += hpack_int(rng, rng.choice([17, 1, 23, 31, 98, 99, 200, rng.randint(0, 120)]), 6,
                             0xC0 if rng.random() < 0.85 else 0x80)
        elif r < 0.7:   # literal with name reference
            out += hpack_int(rng, rng.randint(0, 110), 4, 0x50 if rng.random() < 0.85 else 0x40 | rng.choice([0, 0x20]))
            out += qpack_str(rng, rng.choice(H2_VALUES), 7, 0)
        elif r < 0.9:   # literal with literal name
            out += qpack_str(rng, rng.choice(H2_NAMES), 3, 0x20 | rng.choice([0, 0x10]))
            out += qpack_str(rng, rng.choice(H2_VALUES), 7, 0)
        else:           # post-base forms (need a dynamic table)
            out += hpack_int(rng, rng.randint(0, 10), 4, rng.choice([0x10, 0x00]))
            out += qpack_str(rng, b"v", 7, 0)
    return bytes(out)


def gen_qpack(rng):
    if rng.random() < 0.2:      # encoder / decoder stream instructions
        out = bytearray()
        for _ in range(rng.randint(1, 6)):
            out += rng.choice([hpack_int(rng, rng.randint(0, 5000), 5, 0x20),
                               hpack_int(rng, rng.randint(0, 100), 6, 0x40),
                               hpack_int(rng, rng.randint(0, 100), 7, 0x80),
                               hpack_int(rng, rng.randint(0, 10), 6, 0x00)])
        return bytes(out)
    return gen_qpack_section(rng)


def gen_h3frame(rng):
    out = bytearray()
    for _ in range(rng.randint(1, 6)):
        r = rng.random()
        if r < 0.3:
            p = b"".join(qvarint(rng, rng.choice([1, 6, 7, 2, 3, 4, 5, 0x21, 0x33, rng.randint(0, 1 << 20)])) +
                         qvarint(rng, rng.choice([0, 100, 65536, (1 << 62) - 1, rng.randint(0, 1 << 30)]))
                         for _ in range(rng.randint(0, 5)))
            t = 4
        elif r < 0.6:
            p, t = gen_qpack_section(rng), 1
        elif r < 0.75:
            p, t = rng.randbytes(rng.randint(0, 40)), 0
        else:
            t = rng.choice([3, 5, 7, 13, 2, 6, 8, 9, 0x21, 0x21 + 0x1F * rng.randint(1, 9), rng.randint(0, 1 << 30)])
            p = rng.randbytes(rng.randint(0, 16))
        out += qvarint(rng, t) + qvarint(rng, pick_len(rng, len(p))) + p
    return bytes(out)


# ── TLS ──────────────────────────────────────────────────────────────

def tls_ext(rng, etype, body):
    return u16(etype) + u16(pick_len(rng, len(body))) + body


def vec8(rng, b): return u8(pick_len(rng, len(b))) + b
def vec16(rng, b): return u16(pick_len(rng, len(b))) + b


def gen_client_hello(rng):
    exts = []
    if rng.random() < 0.8:
        name = rng.choice([b"localhost", b"example.com", b"", b"a" * 300, b"x\x00y"])
        exts.append(tls_ext(rng, 0, vec16(rng, u8(0) + vec16(rng, name))))
    groups = [0x001d, 0x0017, 0x11ec, 0x0018, 0x0100, rng.randint(0, 0xFFFF)]
    rng.shuffle(groups)
    groups = groups[:rng.randint(0, len(groups))]
    if rng.random() < 0.9:
        exts.append(tls_ext(rng, 10, vec16(rng, b"".join(u16(g) for g in groups))))
    if rng.random() < 0.9:
        algs = [0x0403, 0x0804, 0x0805, 0x0401, 0x0807, 0x0904, 0x0905, 0x0906, rng.randint(0, 0xFFFF)]
        rng.shuffle(algs)
        exts.append(tls_ext(rng, 13, vec16(rng, b"".join(u16(a) for a in algs[:rng.randint(0, 9)]))))
    if rng.random() < 0.95:
        vers = rng.choice([[0x0304], [0x0304, 0x0303], [0x0303], [0x7f1c, 0x0304], []])
        exts.append(tls_ext(rng, 43, vec8(rng, b"".join(u16(v) for v in vers))))
    if rng.random() < 0.9:
        shares = b""
        for g in (groups or [0x001d])[:rng.randint(0, 3)]:
            klen = {0x001d: 32, 0x0017: 65, 0x0018: 97, 0x11ec: 1216}.get(g, rng.randint(0, 40))
            if rng.random() < 0.2:
                klen = rng.choice([0, 1, klen - 1, klen + 1])
            key = rng.randbytes(max(klen, 0))
            if g == 0x0017 and key:
                key = b"\x04" + key[1:]
            shares += u16(g) + vec16(rng, key)
        exts.append(tls_ext(rng, 51, vec16(rng, shares)))
    if rng.random() < 0.5:
        exts.append(tls_ext(rng, 16, vec16(rng, b"".join(vec8(rng, p) for p in
                                                          rng.sample([b"h2", b"http/1.1", b"", b"x" * 255, b"h3"], rng.randint(0, 4))))))
    if rng.random() < 0.4:
        exts.append(tls_ext(rng, 45, vec8(rng, bytes(rng.sample([0, 1, 2, 255], rng.randint(0, 3))))))
    if rng.random() < 0.15:
        exts.append(tls_ext(rng, 42, b""))
    if rng.random() < 0.15:
        exts.append(tls_ext(rng, 44, vec16(rng, rng.randbytes(rng.randint(0, 40)))))
    if rng.random() < 0.15:
        exts.append(tls_ext(rng, 21, b"\x00" * rng.randint(0, 300)))
    if rng.random() < 0.2:
        exts.append(tls_ext(rng, rng.randint(0, 0xFFFF), rng.randbytes(rng.randint(0, 20))))
    if rng.random() < 0.1 and exts:
        exts.append(rng.choice(exts))                       # duplicate extension
    rng.shuffle(exts)
    if rng.random() < 0.3:                                   # pre_shared_key — must be last
        ids = b"".join(vec16(rng, rng.randbytes(rng.choice([0, 16, 80, 120, rng.randint(0, 200)]))) + u32(rng.randint(0, 1 << 32))
                       for _ in range(rng.randint(0, 3)))
        binders = b"".join(vec8(rng, rng.randbytes(rng.choice([32, 48, 0, 31]))) for _ in range(rng.randint(0, 3)))
        exts.append(tls_ext(rng, 41, vec16(rng, ids) + vec16(rng, binders)))
    suites = [0x1301, 0x1302, 0x1303, 0xc02b, 0x00ff, rng.randint(0, 0xFFFF)]
    rng.shuffle(suites)
    body = (u16(rng.choice([0x0303, 0x0303, 0x0301, 0x0304])) + rng.randbytes(32) +
            vec8(rng, rng.randbytes(rng.choice([0, 32, 32, 33, rng.randint(0, 40)]))) +
            vec16(rng, b"".join(u16(s) for s in suites[:rng.randint(0, 6)])) +
            vec8(rng, rng.choice([b"\x00", b"\x00", b"\x01\x00", b""])) +
            vec16(rng, b"".join(exts)))
    return u8(1) + u24(pick_len(rng, len(body))) + body


def tls_records(rng, ctype, payload):
    """Fragment `payload` into records (RFC 8446 §5.1 — handshake messages
    may span records)."""
    out = bytearray()
    if rng.random() < 0.7:
        pieces = [payload]
    else:
        pieces, off = [], 0
        while off < len(payload):
            n = rng.randint(1, max(1, len(payload) - off))
            pieces.append(payload[off:off + n])
            off += n
    for p in pieces:
        out += u8(ctype) + u16(rng.choice([0x0301, 0x0303, 0x0303, 0x0300, 0x0304])) + u16(pick_len(rng, len(p))) + p
    return bytes(out)


def tls_tail(rng):
    out = bytearray()
    for _ in range(rng.randint(0, 3)):
        r = rng.random()
        if r < 0.3:
            out += u8(20) + u16(0x0303) + u16(1) + b"\x01"          # ChangeCipherSpec
        elif r < 0.6:
            out += tls_records(rng, 23, rng.randbytes(rng.choice([0, 17, 40, 300, 16401, rng.randint(0, 64)])))
        elif r < 0.8:
            out += u8(21) + u16(0x0303) + u16(2) + bytes([rng.choice([1, 2]), rng.randint(0, 120)])
        else:
            out += tls_records(rng, rng.choice([22, 24, 0, 255]), rng.randbytes(rng.randint(0, 30)))
    return bytes(out)


def gen_tls(rng):
    return tls_records(rng, 22, gen_client_hello(rng)) + tls_tail(rng)


HRR_RANDOM = bytes.fromhex("cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c")


def gen_tlscli(rng):
    exts = []
    if rng.random() < 0.95:
        exts.append(tls_ext(rng, 43, u16(rng.choice([0x0304, 0x0304, 0x0303, 0x7f1c]))))
    hrr = rng.random() < 0.2
    if rng.random() < 0.9:
        g = rng.choice([0x001d, 0x0017, 0x11ec, 0x0018, rng.randint(0, 0xFFFF)])
        if hrr:
            exts.append(tls_ext(rng, 51, u16(g)))
        else:
            klen = {0x001d: 32, 0x0017: 65, 0x11ec: 1120}.get(g, rng.randint(0, 40))
            if rng.random() < 0.2:
                klen = rng.choice([0, 1, klen - 1, klen + 1])
            exts.append(tls_ext(rng, 51, u16(g) + vec16(rng, rng.randbytes(max(klen, 0)))))
    if rng.random() < 0.2:
        exts.append(tls_ext(rng, 41, u16(rng.randint(0, 3))))
    if hrr and rng.random() < 0.5:
        exts.append(tls_ext(rng, 44, vec16(rng, rng.randbytes(rng.randint(0, 40)))))
    if rng.random() < 0.15:
        exts.append(tls_ext(rng, rng.randint(0, 0xFFFF), rng.randbytes(rng.randint(0, 10))))
    rng.shuffle(exts)
    body = (u16(0x0303) + (HRR_RANDOM if hrr else rng.randbytes(32)) +
            vec8(rng, rng.randbytes(rng.choice([0, 32, rng.randint(0, 40)]))) +
            u16(rng.choice([0x1301, 0x1302, 0x1303, 0xc02f, rng.randint(0, 0xFFFF)])) +
            u8(rng.choice([0, 0, 1])) + vec16(rng, b"".join(exts)))
    sh = u8(2) + u24(pick_len(rng, len(body))) + body
    out = tls_records(rng, 22, sh)
    if rng.random() < 0.3:                                   # a plaintext message after the hello
        m = rng.choice([8, 11, 15, 20, 4, 13])
        b = rng.randbytes(rng.randint(0, 60))
        out += tls_records(rng, 22, u8(m) + u24(pick_len(rng, len(b))) + b)
    return out + tls_tail(rng)


# ── WebSocket ────────────────────────────────────────────────────────

def ws_frame(rng, fin, rsv, opcode, payload, masked):
    b0 = (0x80 if fin else 0) | (rsv << 4) | opcode
    n = pick_len(rng, len(payload)) if rng.random() < 0.3 else len(payload)
    form = rng.random()
    if n < 126 and form < 0.85:
        hdr = bytes([b0, (0x80 if masked else 0) | n])
    elif n < 65536 and form < 0.95:
        hdr = bytes([b0, (0x80 if masked else 0) | 126]) + u16(n)
    else:
        hdr = bytes([b0, (0x80 if masked else 0) | 127]) + struct.pack(">Q", n if rng.random() < 0.9 else (1 << 63) | n)
    if masked:
        key = rng.randbytes(4)
        payload = bytes(c ^ key[i & 3] for i, c in enumerate(payload))
        hdr += key
    return hdr + payload


def deflate_raw(data):
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    out = c.compress(data) + c.flush(zlib.Z_SYNC_FLUSH)
    return out[:-4] if out.endswith(b"\x00\x00\xff\xff") else out


TEXTS = [b"hello", "héllo €".encode(), b"\xff\xfe", b"\xed\xa0\x80", b"\xf4\x90\x80\x80",
         b"\xc0\xaf", b"a" * 200, b"\xe2\x82", b""]


def gen_ws(rng):
    mode = rng.randint(0, 3)
    deflate = bool(mode & 1)
    masked = not (mode & 2)
    if rng.random() < 0.05:
        masked = not masked
    out = bytearray([mode])
    for _ in range(rng.randint(1, 6)):
        r = rng.random()
        if r < 0.35:
            data = rng.choice(TEXTS)
            rsv = 0
            if deflate and rng.random() < 0.7:
                data = deflate_raw(data if rng.random() < 0.8 else b"\x00" * rng.choice([1 << 16, 1 << 22, 5 << 20]))
                rsv = 4
            op = rng.choice([1, 2])
            if rng.random() < 0.3 and len(data) > 1:     # fragmented
                cut = rng.randint(1, len(data) - 1)
                out += ws_frame(rng, False, rsv, op, data[:cut], masked)
                if rng.random() < 0.3:
                    out += ws_frame(rng, True, 0, 9, b"p", masked)
                out += ws_frame(rng, True, rng.choice([0, 0, 4]), 0, data[cut:], masked)
            else:
                out += ws_frame(rng, True, rsv | rng.choice([0, 0, 0, 0, 1, 2]), op, data, masked)
        elif r < 0.55:
            out += ws_frame(rng, rng.random() < 0.9, 0, rng.choice([9, 10]), rng.randbytes(rng.choice([0, 5, 125, 126, 200])), masked)
        elif r < 0.7:
            body = b"" if rng.random() < 0.2 else u16(rng.choice([1000, 1001, 1005, 1006, 1015, 2999, 3000, 4999, 5000, 0])) + rng.choice(TEXTS)
            if rng.random() < 0.1:
                body = b"\x03"
            out += ws_frame(rng, True, 0, 8, body, masked)
        elif r < 0.8:
            out += ws_frame(rng, rng.random() < 0.5, 0, 0, rng.randbytes(rng.randint(0, 20)), masked)
        else:
            out += ws_frame(rng, rng.random() < 0.5, rng.randint(0, 7), rng.choice([3, 4, 7, 11, 15]), rng.randbytes(rng.randint(0, 20)), masked)
    return bytes(out)


# ── MQTT ─────────────────────────────────────────────────────────────

def mqtt_varint(rng, v):
    out = bytearray()
    while True:
        b = v & 127
        v >>= 7
        if v:
            out.append(b | 128)
        else:
            out.append(b)
            break
    if rng.random() < 0.03:
        out = bytearray(b"\xff\xff\xff\xff\x7f")       # 5-byte varint: malformed
    return bytes(out)


def mqtt_str(rng, s): return u16(pick_len(rng, len(s))) + s


def mqtt_props(rng):
    p = bytearray()
    for _ in range(rng.randint(0, 5)):
        pid = rng.choice([0x01, 0x02, 0x03, 0x08, 0x09, 0x0B, 0x11, 0x23, 0x26, 0x26, 0x1F, rng.randint(0, 0x30)])
        if pid in (0x01, 0x17, 0x19, 0x24, 0x25, 0x28, 0x29, 0x2A):
            p += u8(pid) + u8(rng.randint(0, 2))
        elif pid in (0x02, 0x11, 0x18, 0x27):
            p += u8(pid) + u32(rng.randint(0, 1 << 32))
        elif pid in (0x03, 0x08, 0x12, 0x15, 0x1A, 0x1C, 0x1F):
            p += u8(pid) + mqtt_str(rng, rng.choice(TEXTS))
        elif pid in (0x09, 0x16):
            p += u8(pid) + mqtt_str(rng, rng.randbytes(rng.randint(0, 20)))
        elif pid == 0x0B:
            p += u8(pid) + mqtt_varint(rng, rng.randint(0, 1 << 28))
        elif pid in (0x13, 0x21, 0x22, 0x23):
            p += u8(pid) + u16(rng.randint(0, 0xFFFF))
        elif pid == 0x26:
            p += u8(pid) + mqtt_str(rng, rng.choice(TEXTS)) + mqtt_str(rng, rng.choice(TEXTS))
        else:
            p += u8(pid) + rng.randbytes(rng.randint(0, 4))
    return mqtt_varint(rng, pick_len(rng, len(p))) + bytes(p)


def gen_mqtt(rng):
    out = bytearray()
    for _ in range(rng.randint(1, 6)):
        r = rng.random()
        if r < 0.5:
            qos = rng.choice([0, 0, 1, 2, 3])
            flags = (qos << 1) | rng.choice([0, 1]) | rng.choice([0, 8])
            body = mqtt_str(rng, rng.choice([b"a/b", b"", b"t" * 300, "ü/#".encode(), b"\x00"]))
            if qos:
                body += u16(rng.randint(0, 0xFFFF))
            body += mqtt_props(rng) + rng.randbytes(rng.randint(0, 40))
            out += u8(0x30 | flags) + mqtt_varint(rng, pick_len(rng, len(body))) + body
        elif r < 0.85:
            t = rng.choice([0x40, 0x50, 0x62, 0x70, 0x90, 0xB0, 0xD0, 0xE0, 0xF0, 0x20, 0x00])
            body = u16(rng.randint(0, 3)) + (u8(rng.randint(0, 0x9F)) if rng.random() < 0.6 else b"")
            if rng.random() < 0.5:
                body += mqtt_props(rng)
            if t == 0xD0 and rng.random() < 0.7:
                body = b""
            out += u8(t) + mqtt_varint(rng, pick_len(rng, len(body))) + body
        else:
            out += u8(rng.randint(0, 255)) + mqtt_varint(rng, rng.choice([0, 1, 127, 128, 16383, 2097151, 268435455]))
    return bytes(out)


# ── HTTP/1.1 ─────────────────────────────────────────────────────────

# Each field is valid most of the time and odd now and then (`odd`), so a
# message usually gets through the line parser to the framing and body
# logic — a generator whose every message trips on the request line only
# ever tests the request line.
ODD = 0.12


def odd(rng, ok, bad, p=ODD):
    return rng.choice(bad) if rng.random() < p else rng.choice(ok)


METHODS = ([b"GET", b"POST", b"PUT", b"HEAD", b"DELETE"],
           [b"OPTIONS", b"CONNECT", b"PRI", b"get", b"G\x00T", b"", b"X" * 40])
TARGETS_ = ([b"/", b"/a/b?c=d&e=%41", b"/x?k=v&k=w", b"/static/f.txt"],
            [b"*", b"http://h/x?y", b"//x", b"/%zz", b"/" + b"a" * 9000, b"/a b", b"?", b"/\x00"])
VERSIONS = ([b"HTTP/1.1", b"HTTP/1.1", b"HTTP/1.0"],
            [b"HTTP/2.0", b"HTTP/1.10", b"http/1.1", b"HTTP/9", b"", b"HTTP/1.1 "])


def http_headers(rng, body_kind):
    hs = []
    if rng.random() < 0.95:
        hs.append(b"Host: " + odd(rng, [b"x", b"localhost:8080"], [b"", b"a:1", b"x, y"]))
    for _ in range(rng.randint(0, 5)):
        hs.append(odd(rng, [
            b"Connection: " + rng.choice([b"close", b"keep-alive", b"keep-alive"]),
            b"Content-Type: " + rng.choice([b"text/plain", b"multipart/form-data; boundary=b",
                                             b"application/x-www-form-urlencoded"]),
            b"X-" + rng.randbytes(3).hex().encode() + b": " + rng.choice(TEXTS[:3]),
            b"Cookie: a=b; c=d", b"Accept: */*", b"Range: bytes=0-1,-5",
            b"Authorization: Basic Zm9vOmJhcg==", b"Expect: 100-continue",
        ], [
            b"Connection: " + rng.choice([b"Upgrade", b"close, te", b""]),
            b"Upgrade: " + rng.choice([b"websocket", b"h2c"]),
            b"Bad Header: v", b"NoColon", b": novalue", b" lead: ws",
            b"X: a\r\n folded", b"X:" + b"v" * rng.choice([8200, 70000]),
            b"X-" + rng.randbytes(2).hex().encode() + b": " + rng.choice(TEXTS),
        ], 0.2))
    if body_kind == "cl":
        hs.append(b"Content-Length: " + odd(rng, [b"{n}"], [b"+{n}", b"0x{n}", b" {n} ", b"{n}, {n}", b"{n},{n}",
                                                         b"-1", b"99999999999999999999", b""]))
    elif body_kind == "chunked":
        hs.append(b"Transfer-Encoding: " + odd(rng, [b"chunked", b"Chunked"],
                                               [b" chunked", b"gzip, chunked", b"chunked, gzip", b"chunked\x0b",
                                                b"identity", b"chunked, chunked"]))
        if rng.random() < 0.08:
            hs.append(b"Content-Length: 3")
    if rng.random() < 0.03:
        hs = hs * rng.randint(20, 120)                   # header-count limit
    rng.shuffle(hs)
    return hs


def http_chunked_body(rng):
    out = bytearray()
    for _ in range(rng.randint(0, 4)):
        data = rng.randbytes(rng.randint(0, 40))
        size = odd(rng, [b"%x" % len(data), b"%X" % len(data)],
                   [b"000%x" % len(data), b"%x;ext=v" % len(data), b"%x ;e" % len(data),
                    b"FFFFFFFFFFFFFFFF", b"10000000000000000", b"-1", b"", b"0x5", b"7fffffffffffffff",
                    b"%x" % (len(data) + 1), b"C000000000000000"])
        out += size + odd(rng, [b"\r\n"], [b"\n", b"\r"]) + data + odd(rng, [b"\r\n"], [b"X\r\n", b"", b"\n"])
    out += b"0" + odd(rng, [b""], [b";x=y", b"0000"]) + b"\r\n"
    for _ in range(odd(rng, [0, 0, 1], [2, 70])):
        out += b"Trailer-" + rng.randbytes(2).hex().encode() + b": v\r\n"
    if rng.random() < 0.95:
        out += b"\r\n"
    return bytes(out)


def gen_http1(rng):
    out = bytearray()
    for _ in range(rng.randint(1, 4)):
        kind = rng.choice(["none", "none", "cl", "chunked"])
        eol = odd(rng, [b"\r\n"], [b"\n"], 0.04)
        line = odd(rng, *METHODS) + b" " + odd(rng, *TARGETS_) + b" " + odd(rng, *VERSIONS)
        if rng.random() < 0.04:
            line = line.replace(b" ", rng.choice([b"  ", b"\t", b""]), 1)
        body = b""
        if kind == "cl":
            body = rng.randbytes(rng.randint(0, 64))
        elif kind == "chunked":
            body = http_chunked_body(rng)
        n = str(len(body) if rng.random() < 0.9 else rng.randint(0, 200)).encode()
        hs = [h.replace(b"{n}", n) for h in http_headers(rng, kind)]
        out += line + eol + eol.join(hs) + (eol if hs else b"") + eol + body
    return bytes(out)


def gen_http1resp(rng):
    out = bytearray()
    for _ in range(odd(rng, [0, 0, 1], [2, 40])):         # interim 1xx responses
        out += b"HTTP/1.1 " + rng.choice([b"100 Continue", b"103 Early Hints", b"101 Switching"]) + b"\r\n\r\n"
    kind = rng.choice(["none", "cl", "cl", "chunked", "eof"])
    body = b""
    if kind in ("cl", "eof"):
        body = rng.randbytes(rng.randint(0, 64))
    elif kind == "chunked":
        body = http_chunked_body(rng)
    status = odd(rng, [b"200 OK", b"200 OK", b"204 No Content", b"304 Not Modified", b"404 Not Found"],
                 [b"200", b"999 X", b"-1 X", b"abc", b"20 short", b"200 " + b"r" * 9000])
    n = str(len(body) if rng.random() < 0.9 else rng.randint(0, 200)).encode()
    hs = [h.replace(b"{n}", n) for h in http_headers(rng, kind if kind != "eof" else "none")
          if not h.startswith(b"Host")]
    if rng.random() < 0.3:
        hs.append(b"Set-Cookie: s=1; Path=/; HttpOnly")
    if rng.random() < 0.1:
        hs.append(b"Location: /elsewhere")
    if kind == "eof":
        hs.append(b"Connection: close")
    ver = odd(rng, [b"HTTP/1.1", b"HTTP/1.1", b"HTTP/1.0"], [b"HTTP/2", b"HTTX/1.1", b""])
    out += ver + b" " + status + b"\r\n" + b"\r\n".join(hs) + (b"\r\n" if hs else b"") + b"\r\n" + body
    return bytes(out)


def gen_multipart(rng):
    b = rng.choice([b"XyZ", b"b", b"----WebKitFormBoundary7MA4YWxkTrZu0gW", b"a" * 70, b"--", b"\r"])
    out = bytearray(b + b"\n")
    for _ in range(rng.randint(0, 5)):
        out += b"--" + b + rng.choice([b"\r\n", b"\r\n", b"\n", b"  \r\n"])
        if rng.random() < 0.9:
            out += b"Content-Disposition: " + rng.choice([b"form-data", b"attachment", b"Form-Data"])
            out += rng.choice([b'; name="a"', b"; name=a", b'; name="fi\\"le"', b'; name="', b""])
            out += rng.choice([b"", b'; filename="f.txt"', b"; filename*=UTF-8''%e2%82%ac", b'; filename=""'])
            out += b"\r\n"
        if rng.random() < 0.5:
            out += b"Content-Type: " + rng.choice([b"text/plain", b"", b"application/octet-stream"]) + b"\r\n"
        out += rng.choice([b"\r\n", b"\r\n", b""])
        out += rng.randbytes(rng.randint(0, 40)) + rng.choice([b"", b"\r\n--" + b[:-1]]) + b"\r\n"
    out += b"--" + b + rng.choice([b"--\r\n", b"--", b"", b"-"])
    return bytes(out)


def gen_urlish(rng):
    r = rng.random()
    if r < 0.5:
        u = (rng.choice([b"http://", b"https://", b"ws://", b"HTTP://", b"", b"://", b"x+y.z:"]) +
             rng.choice([b"", b"user@", b"u:p@", b"@", b"%40@"]) +
             rng.choice([b"example.com", b"[::1]", b"[::1", b"1.2.3.4", b"", b"h\x7f"]) +
             rng.choice([b"", b":80", b":", b":99999", b":-1", b":0x50"]) +
             rng.choice([b"", b"/", b"/a/../b", b"/%20%zz%", b"/" + b"%41" * 200]) +
             rng.choice([b"", b"?a=1&b=%2", b"?&&==", b"?k", b"?+%2B+"]) +
             rng.choice([b"", b"#f", b"#"]))
        return u
    if r < 0.8:
        parts = [rng.choice([b"n=v", b"=v", b"n=", b"n", b"", b"n=\"q\""])]
        for _ in range(rng.randint(0, 6)):
            parts.append(rng.choice([b"Domain=" + rng.choice([b".example.com", b"example.com", b"com", b"", b"other.org"]),
                                     b"Path=" + rng.choice([b"/", b"/a", b"", b"a"]),
                                     b"Max-Age=" + rng.choice([b"0", b"-5", b"99999999999999999999", b"x"]),
                                     b"Expires=" + rng.choice([b"Wed, 21 Oct 2015 07:28:00 GMT", b"garbage", b"Thu, 01 Jan 1970 00:00:00 GMT", b""]),
                                     b"Secure", b"HttpOnly", b"SameSite=None", b"", b"=", b";"]))
        return b";".join(p if rng.random() < 0.5 else b" " + p for p in parts)
    params = [b"permessage-deflate"]
    for _ in range(rng.randint(0, 4)):
        params.append(rng.choice([b"client_max_window_bits", b"client_max_window_bits=" + rng.choice([b"8", b"15", b"16", b"7", b"x", b""]),
                                  b"server_max_window_bits=" + rng.choice([b"9", b"15", b"0", b"99999999999999999999"]),
                                  b"server_no_context_takeover", b"client_no_context_takeover", b"unknown=1"]))
    return b"; ".join(params) + rng.choice([b"", b", permessage-deflate", b","])


# ── DER (x509, CSR, the TLS Certificate message) ─────────────────────
#
# Structure-aware: parse the TLV tree, change ONE node (its bytes, its
# tag, a length lie, a duplicate, a deletion, a big INTEGER), then
# re-encode with every enclosing length recomputed — so the mutation
# reaches the field parsers instead of failing the outermost length.

DER_CONSTRUCTED = {0x30, 0x31, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8}


def der_parse(b, off=0, end=None, depth=0):
    end = len(b) if end is None else end
    nodes = []
    while off < end:
        if end - off < 2:
            return None
        tag = b[off]
        ln = b[off + 1]
        p = off + 2
        if ln & 0x80:
            k = ln & 0x7F
            if k == 0 or k > 4 or p + k > end:
                return None
            ln = int.from_bytes(b[p:p + k], "big")
            p += k
        if p + ln > end:
            return None
        body = b[p:p + ln]
        kids = None
        if depth < 12 and (tag in DER_CONSTRUCTED or tag == 0x04 or (tag == 0x03 and body[:1] == b"\x00")):
            inner = body[1:] if tag == 0x03 else body
            kids = der_parse(inner, 0, None, depth + 1) if inner else None
            if tag not in DER_CONSTRUCTED and kids is not None and not kids:
                kids = None
        nodes.append([tag, body, kids])
        off = p + ln
    return nodes


def der_len(rng, n):
    if rng.random() < 0.03:
        return rng.choice([b"\x80", b"\x84\xff\xff\xff\xff", b"\x81\x01", b"\x83" + n.to_bytes(3, "big")])
    if n < 128:
        return bytes([n])
    k = (n.bit_length() + 7) // 8
    return bytes([0x80 | k]) + n.to_bytes(k, "big")


def der_encode(rng, nodes):
    out = bytearray()
    for tag, body, kids in nodes:
        if kids is not None:
            inner = der_encode(rng, kids)
            body = (b"\x00" + inner) if tag == 0x03 else inner
        out += bytes([tag]) + der_len(rng, len(body)) + body
    return bytes(out)


def der_walk(nodes, acc):
    for n in nodes:
        acc.append((nodes, n))
        if n[2] is not None:
            der_walk(n[2], acc)
    return acc


def der_mutate(data, rng):
    tree = der_parse(data)
    if not tree:
        return mutate(data, rng)
    for _ in range(rng.randint(1, 3)):
        sites = der_walk(tree, [])
        parent, node = rng.choice(sites)
        op = rng.randint(0, 7)
        if op == 0:
            node[1], node[2] = mutate(node[1], rng), None
        elif op == 1:
            node[0] = rng.choice([0x02, 0x03, 0x04, 0x05, 0x06, 0x0C, 0x13, 0x17, 0x18, 0x30, 0x31, 0x80, 0xA0, 0xA3, rng.randint(0, 255)])
        elif op == 2 and len(parent) < 64:
            parent.insert(parent.index(node), [node[0], node[1], node[2]])
        elif op == 3 and len(parent) > 1:
            parent.remove(node)
        elif op == 4:
            node[1], node[2] = rng.choice([b"", b"\x00", b"\xff" * rng.randint(1, 600), b"\x00" * 40, rng.randbytes(rng.randint(1, 40))]), None
        elif op == 5:
            node[0], node[1], node[2] = 0x02, rng.choice([b"\x00", b"\x80", b"\x00\x80", b"\x7f" + b"\xff" * 600, b"\x01" + b"\x00" * 520]), None
        elif op == 6:
            node[0], node[1], node[2] = 0x06, rng.choice([bytes.fromhex("2a864886f70d010101"), bytes.fromhex("2a8648ce3d0201"),
                                                          bytes.fromhex("2b6570"), bytes.fromhex("608648016503040311"), b"\xff" * 12, b""]), None
        else:
            node[0], node[1], node[2] = rng.choice([0x17, 0x18]), rng.choice([b"991231235959Z", b"500101000000Z", b"20991231235959Z",
                                                                                b"0", b"9912312359", b"19700101000000+0100"]), None
    return der_encode(rng, tree)


def corpus_or(fmt, fallback):
    c = load_corpus(fmt)
    return c if c else fallback


def gen_x509(rng):
    return der_mutate(rng.choice(corpus_or("x509", BINARY_SEEDS["x509"])), rng)


def gen_csr(rng):
    return der_mutate(rng.choice(corpus_or("csr", [b"\x30\x00"])), rng)


def gen_tlscert(rng):
    certs = corpus_or("x509", BINARY_SEEDS["x509"])
    is12 = rng.random() < 0.3
    chain = [rng.choice(certs) for _ in range(rng.choice([1, 1, 2, 2, 3, 17]))]
    chain = [der_mutate(c, rng) if rng.random() < 0.5 else c for c in chain]
    lst = bytearray()
    for c in chain:
        lst += u24(pick_len(rng, len(c))) + c
        if not is12:
            ext = rng.choice([b"", b"", b"\x00\x05\x00\x01\x00", rng.randbytes(rng.randint(0, 9))])
            lst += u16(pick_len(rng, len(ext))) + ext
    body = (b"" if is12 else vec8(rng, rng.choice([b"", b"", rng.randbytes(rng.randint(1, 8))]))) + u24(pick_len(rng, len(lst))) + bytes(lst)
    return bytes([1 if is12 else 0]) + u8(11) + u24(pick_len(rng, len(body))) + body


def gen_pem(rng):
    import base64
    der = gen_csr(rng) if rng.random() < 0.3 else gen_x509(rng)
    label = rng.choice([b"CERTIFICATE", b"CERTIFICATE REQUEST", b"NEW CERTIFICATE REQUEST", b"PRIVATE KEY", b"X"])
    b64 = base64.b64encode(der)
    if rng.random() < 0.2:
        b64 = mutate(b64, rng)
    width = rng.choice([64, 64, 76, 1, 0])
    lines = [b64[i:i + width] for i in range(0, len(b64), width)] if width else [b64]
    eol = rng.choice([b"\n", b"\r\n", b"\n\n"])
    out = b"-----BEGIN " + label + b"-----" + eol + eol.join(lines) + eol
    if rng.random() < 0.9:
        out += b"-----END " + label + b"-----" + eol
    return out


GENERATORS = {
    "hpack": gen_hpack, "h2frame": gen_h2frame, "h2": gen_h2, "qpack": gen_qpack,
    "h3frame": gen_h3frame, "tls": gen_tls, "tlscli": gen_tlscli, "ws": gen_ws,
    "mqtt": gen_mqtt, "http1": gen_http1, "http1resp": gen_http1resp,
    "multipart": gen_multipart, "urlish": gen_urlish,
    "x509": gen_x509, "csr": gen_csr, "tlscert": gen_tlscert, "pem": gen_pem,
}

# Inputs per harness run. Socket targets set up a connection per input;
# the TLS server mints a key share and signs per handshake.
BATCH = {"tls": 8, "tlscli": 16, "http1": 16, "h2": 16, "ws": 16, "http1resp": 16, "mqtt": 16}
DEFAULT_BATCH = 64

SEEDS = {}
for f, ss in TEXT_SEEDS.items():
    SEEDS[f] = ss
for f, ss in BINARY_SEEDS.items():
    SEEDS[f] = ss
for f in list(SEEDS):
    SEEDS[f] = SEEDS[f] + load_corpus(f)


def mutate(data: bytes, rng: random.Random) -> bytes:
    b = bytearray(data)
    for _ in range(rng.randint(1, 6)):
        if not b:
            b = bytearray(rng.randbytes(rng.randint(1, 8)))
            continue
        op = rng.randint(0, 8)
        i = rng.randrange(len(b))
        if op == 0:                       # flip a byte
            b[i] ^= 1 << rng.randint(0, 7)
        elif op == 1:                     # set to an interesting byte
            b[i] = rng.choice([0, 0xFF, 0x7F, 0x80, 0x30, 0x82, 0x0A, 0x0D, 0x5B, 0x3A, 0x20])
        elif op == 2:                     # delete a byte
            del b[i]
        elif op == 3:                     # insert a byte
            b.insert(i, rng.randint(0, 255))
        elif op == 4:                     # duplicate a slice (length inflation)
            j = rng.randrange(len(b))
            lo, hi = min(i, j), max(i, j)
            b[lo:lo] = b[lo:hi + 1]
        elif op == 5:                     # truncate
            b = b[:i]
        elif op == 6:                     # repeat a byte (nesting / length DoS)
            b[i:i] = bytes([b[i]]) * rng.randint(50, 3000)
        elif op == 7:                     # overwrite with an interesting big-endian word
            w = rng.choice([b"\xff\xff", b"\x7f\xff\xff\xff", b"\x00\x00", b"\x80\x00\x00\x00",
                            b"\x3f\xff", b"\xff\xff\xff\xff\xff\xff\xff\xff"])
            b[i:i + len(w)] = w
        else:                             # splice random bytes
            b[i:i] = rng.randbytes(rng.randint(1, 16))
    return bytes(b)


def make_input(fmt, rng):
    gen = GENERATORS.get(fmt)
    seeds = SEEDS.get(fmt, [])
    if gen and (not seeds or rng.random() < 0.6):
        data = gen(rng)
        return data if rng.random() < 0.5 else mutate(data, rng)
    return mutate(rng.choice(seeds), rng)


def is_finding(rc: int, stderr: bytes, timed_out: bool) -> str:
    if timed_out:
        return "timeout (hang / unbounded recursion)"
    marks = (b"AddressSanitizer", b"UndefinedBehaviorSanitizer", b"runtime error:",
             b"LeakSanitizer", b"rss_limit", b"allocation-size-too-big")
    if any(m in stderr for m in marks):
        return "sanitizer report"
    if rc < 0:
        return f"killed by signal {-rc}"
    # harness returns 0 (parsed or graceful error) or 2 (usage/unknown).
    if rc not in (0, 2):
        return f"non-zero exit {rc}"
    return ""


class Runner:
    def __init__(self, args):
        self.args = args
        self.env = dict(os.environ,
                        ASAN_OPTIONS=("detect_leaks=1:abort_on_error=1:halt_on_error=1:"
                                      f"max_allocation_size_mb={args.max_alloc_mb}:"
                                      "allocator_may_return_null=0:"
                                      f"hard_rss_limit_mb={args.rss_mb}"),
                        UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
        self.lock = threading.Lock()

    def run(self, fmt, paths, timeout):
        try:
            p = subprocess.run([self.args.harness, fmt] + paths, env=self.env,
                               capture_output=True, timeout=timeout)
            return p.returncode, p.stderr, False
        except subprocess.TimeoutExpired as e:
            return 0, e.stderr or b"", True

    def campaign(self, fmt, rng, tmp, budget_iters, deadline, tag_seed, stats):
        """Run inputs for `fmt` until the iteration budget or the deadline."""
        bsz = self.args.batch or BATCH.get(fmt, DEFAULT_BATCH)
        it = 0
        start = last_note = time.time()
        while (budget_iters is None or it < budget_iters) and (deadline is None or time.time() < deadline):
            if deadline is not None and time.time() - last_note > 600:
                last_note = time.time()
                print(f"[{fmt}] … {stats['execs']} execs, {(last_note - start) / 60:.0f} min, "
                      f"findings={stats['findings']}", flush=True)
            n = bsz if budget_iters is None else min(bsz, budget_iters - it)
            datas = [make_input(fmt, rng) for _ in range(n)]
            paths = []
            for k, d in enumerate(datas):
                p = os.path.join(tmp, f"in{k}")
                with open(p, "wb") as fh:
                    fh.write(d)
                paths.append(p)
            batch_timeout = self.args.timeout * (1 + n / 8)
            rc, err, to = self.run(fmt, paths, batch_timeout)
            why = is_finding(rc, err, to)
            if why:
                self.triage(fmt, datas, paths, why, err, tag_seed, it, stats)
            it += n
            stats["execs"] += n
        return it

    def triage(self, fmt, datas, paths, why, err, tag_seed, it, stats):
        for k, p in enumerate(paths):
            rc1, err1, to1 = self.run(fmt, [p], self.args.timeout)
            why1 = is_finding(rc1, err1, to1)
            if why1:
                self.save(fmt, f"parse_{fmt}_seed{tag_seed}_it{it + k}", [datas[k]], why1, err1, stats)
                return
        self.save(fmt, f"parse_{fmt}_seed{tag_seed}_it{it}_batch", datas, why + " (batch only)", err, stats)

    def save(self, fmt, tag, datas, why, err, stats):
        with self.lock:
            stats["findings"] += 1
            if len(datas) == 1:
                with open(os.path.join(FAILDIR, tag + ".bin"), "wb") as fh:
                    fh.write(datas[0])
            else:
                d = os.path.join(FAILDIR, tag)
                os.makedirs(d, exist_ok=True)
                for k, data in enumerate(datas):
                    with open(os.path.join(d, f"in{k:03d}.bin"), "wb") as fh:
                        fh.write(data)
            with open(os.path.join(FAILDIR, tag + ".log"), "wb") as fh:
                fh.write(b"format: " + fmt.encode() + b"\nreason: " +
                         why.encode() + b"\n\n" + err[-20000:])
            print(f"FINDING [{fmt}] {tag}: {why}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--harness", required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--iters", type=int, default=2000)
    ap.add_argument("--minutes", type=float, default=0.0,
                    help="time budget PER TARGET (overrides --iters)")
    ap.add_argument("--jobs", type=int, default=1, help="targets run side by side (--minutes mode)")
    ap.add_argument("--batch", type=int, default=0, help="inputs per harness run (0 = per-target default)")
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--max-alloc-mb", type=int, default=1024)
    ap.add_argument("--rss-mb", type=int, default=3072)
    ap.add_argument("--formats", default=",".join(SEEDS.keys()))
    ap.add_argument("--summary", default="", help="write a JSON run summary here (report.py input)")
    args = ap.parse_args()

    formats = [f for f in args.formats.split(",") if f in SEEDS]
    os.makedirs(FAILDIR, exist_ok=True)
    runner = Runner(args)
    per = {f: {"execs": 0, "findings": 0, "seconds": 0.0} for f in formats}
    t0 = time.time()

    if args.minutes > 0:
        queue = list(formats)
        qlock = threading.Lock()

        def worker():
            while True:
                with qlock:
                    if not queue:
                        return
                    fmt = queue.pop(0)
                rng = random.Random(f"{args.seed}:{fmt}")
                start = time.time()
                with tempfile.TemporaryDirectory() as tmp:
                    runner.campaign(fmt, rng, tmp, None, start + args.minutes * 60, args.seed, per[fmt])
                per[fmt]["seconds"] = time.time() - start
                print(f"[{fmt}] {per[fmt]['execs']} execs in {per[fmt]['seconds'] / 60:.1f} min, "
                      f"findings={per[fmt]['findings']}", flush=True)

        threads = [threading.Thread(target=worker) for _ in range(max(1, args.jobs))]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
    else:
        rng = random.Random(args.seed)
        with tempfile.TemporaryDirectory() as tmp:
            # The classic mode: targets drawn at random, one batch at a time.
            done = 0
            while done < args.iters:
                fmt = rng.choice(formats)
                bsz = min(args.batch or BATCH.get(fmt, DEFAULT_BATCH), args.iters - done)
                start = time.time()
                done += runner.campaign(fmt, rng, tmp, bsz, None, args.seed, per[fmt])
                per[fmt]["seconds"] += time.time() - start

    execs = sum(p["execs"] for p in per.values())
    findings = sum(p["findings"] for p in per.values())
    print("─" * 42)
    for f in formats:
        p = per[f]
        print(f"  {f:10s} {p['execs']:8d} execs {p['seconds'] / 60:7.1f} min  findings={p['findings']}")
    print(f"seed={args.seed} execs={execs} formats={','.join(formats)} "
          f"findings={findings} wall={(time.time() - t0) / 60:.1f} min")
    if args.summary:
        os.makedirs(os.path.dirname(args.summary) or ".", exist_ok=True)
        with open(args.summary, "w") as fh:
            json.dump({"family": "parser-mutational", "generator": "fuzz_parsers.py",
                       "seed_start": args.seed, "seed_count": 1,
                       "size": execs, "depth": 0, "minutes": args.minutes,
                       "pass": execs - findings, "findings": findings,
                       "buildfail": 0, "san_runs": execs,
                       "san_findings": findings,
                       "targets": {f: {"execs": p["execs"], "minutes": round(p["seconds"] / 60, 1),
                                       "findings": p["findings"]} for f, p in per.items()}},
                      fh, indent=2)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
