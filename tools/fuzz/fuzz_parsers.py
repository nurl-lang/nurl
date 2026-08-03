#!/usr/bin/env python3
# tools/fuzz/fuzz_parsers.py — mutational fuzzer for the untrusted-input
# parsers (x509/DER, cbor, msgpack, json, yaml, xml, toml).
#
# It mutates format-appropriate seeds and runs the ASan+UBSan-built harness
# (tools/fuzz/parse_harness) on each. A parser must ALWAYS finish with either
# a value or a graceful error — never a crash, out-of-bounds access, UB, or a
# hang. So a finding is any of:
#     * non-zero / signal exit from the harness (abort, SIGSEGV, SIGFPE, …)
#     * an AddressSanitizer / UndefinedBehaviorSanitizer report on stderr
#     * a timeout (a hang or unbounded recursion the OS hasn't killed yet)
#
# Deterministic per --seed, so a finding reproduces. Failing inputs are saved
# under tools/fuzz/failures/ for triage.
#
# Usage:
#   fuzz_parsers.py --harness <bin> [--seed N] [--iters N] [--timeout SEC]
#                   [--formats a,b,...]

import argparse
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAILDIR = os.path.join(ROOT, "tools", "fuzz", "failures")

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
}

SEEDS = {}
for f, ss in TEXT_SEEDS.items():
    SEEDS[f] = [("text", s) for s in ss]
for f, ss in BINARY_SEEDS.items():
    SEEDS[f] = [("bin", s) for s in ss]


def mutate(data: bytes, rng: random.Random) -> bytes:
    b = bytearray(data)
    for _ in range(rng.randint(1, 6)):
        if not b:
            b = bytearray(rng.randbytes(rng.randint(1, 8)))
            continue
        op = rng.randint(0, 7)
        i = rng.randrange(len(b))
        if op == 0:                       # flip a byte
            b[i] ^= 1 << rng.randint(0, 7)
        elif op == 1:                     # set to an interesting byte
            b[i] = rng.choice([0, 0xFF, 0x7F, 0x80, 0x30, 0x82, 0x0A, 0x5B])
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
        else:                             # splice random bytes
            b[i:i] = rng.randbytes(rng.randint(1, 16))
    return bytes(b)


def is_finding(rc: int, stderr: bytes, timed_out: bool) -> str:
    if timed_out:
        return "timeout (hang / unbounded recursion)"
    if rc < 0:
        return f"killed by signal {-rc}"
    # harness returns 0 (parsed or graceful error) or 2 (usage/unknown).
    if rc not in (0, 2):
        return f"non-zero exit {rc}"
    marks = (b"AddressSanitizer", b"UndefinedBehaviorSanitizer", b"runtime error:")
    if any(m in stderr for m in marks):
        return "sanitizer report"
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--harness", required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--iters", type=int, default=2000)
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--formats", default=",".join(SEEDS.keys()))
    ap.add_argument("--summary", default="", help="write a JSON run summary here (report.py input)")
    args = ap.parse_args()

    formats = [f for f in args.formats.split(",") if f in SEEDS]
    rng = random.Random(args.seed)
    os.makedirs(FAILDIR, exist_ok=True)
    env = dict(os.environ,
               ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:halt_on_error=1",
               UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")

    findings = 0
    with tempfile.TemporaryDirectory() as tmp:
        inp = os.path.join(tmp, "in")
        for it in range(args.iters):
            fmt = rng.choice(formats)
            kind, seed = rng.choice(SEEDS[fmt])
            data = mutate(seed, rng)
            with open(inp, "wb") as fh:
                fh.write(data)
            timed_out = False
            try:
                p = subprocess.run([args.harness, fmt, inp], env=env,
                                   capture_output=True, timeout=args.timeout)
                rc, err = p.returncode, p.stderr
            except subprocess.TimeoutExpired:
                timed_out, rc, err = True, 0, b""
            why = is_finding(rc, err, timed_out)
            if why:
                findings += 1
                tag = f"parse_{fmt}_seed{args.seed}_it{it}"
                with open(os.path.join(FAILDIR, tag + ".bin"), "wb") as fh:
                    fh.write(data)
                with open(os.path.join(FAILDIR, tag + ".log"), "wb") as fh:
                    fh.write(b"format: " + fmt.encode() + b"\nreason: " +
                             why.encode() + b"\n\n" + err)
                print(f"FINDING [{fmt}] it={it}: {why}  → {tag}.bin", flush=True)

    print("─" * 42)
    print(f"seed={args.seed} iters={args.iters} formats={','.join(formats)} "
          f"findings={findings}")
    if args.summary:
        import json
        os.makedirs(os.path.dirname(args.summary) or ".", exist_ok=True)
        with open(args.summary, "w") as fh:
            json.dump({"family": "parser-mutational", "generator": "fuzz_parsers.py",
                       "seed_start": args.seed, "seed_count": 1,
                       "size": args.iters, "depth": 0,
                       "pass": args.iters - findings, "findings": findings,
                       "buildfail": 0, "san_runs": args.iters,
                       "san_findings": findings}, fh, indent=2)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
