#!/usr/bin/env python3
# bench/gen_pq_results.py — render bench/PQ_RESULTS.md from the flat
# measurement rows bench/run_pq.sh feeds on stdin. Not meant to be run
# by hand; run_pq.sh drives it and overwrites PQ_RESULTS.md with the
# result, the same way run_http.sh generates bench/HTTP_RESULTS.md.
#
# Input (on stdin, all tab-separated):
#   ENV\tkey\tvalue                one per environment field
#   ROW\t<name>\t<ns_op>\t<iters>\t<impl>   one per (operation, run)
#   THR\t<name>\t<mb_s>\t<impl>             one per (throughput op, run)
# impl is nurl|rust. Repeated rows for the same (name, impl) are
# medians-of-runs. Operation names come from the harnesses
# (bench/pq_compare.nu and bench/rust_pq) and must match between them.

import sys
from statistics import median

IMPLS = [("nurl", "NURL"), ("rust", "Rust")]

# Report layout: one table per scheme family, operations in the order
# the harnesses emit them. Anything not matched falls into "Other".
FAMILIES = [
    ("ML-KEM (FIPS 203)", "ML-KEM-"),
    ("ML-DSA (FIPS 204)", "ML-DSA-"),
    ("SLH-DSA (FIPS 205)", "SLH-DSA-"),
]


def main():
    env = {}
    rows = {}      # (name, impl) -> [ns_op, ...]
    thr = {}       # (name, impl) -> [mb_s, ...]
    order = []     # operation names, first-seen order
    for line in sys.stdin:
        f = line.rstrip("\n").split("\t")
        if f[0] == "ENV" and len(f) >= 3:
            env[f[1]] = "\t".join(f[2:])
        elif f[0] == "ROW" and len(f) == 5:
            _, name, ns, _iters, impl = f
            rows.setdefault((name, impl), []).append(int(ns))
            if name not in order:
                order.append(name)
        elif f[0] == "THR" and len(f) == 4:
            _, name, mb_s, impl = f
            thr.setdefault((name, impl), []).append(int(mb_s))
            if name not in order:
                order.append(name)

    def med(d, name, impl):
        v = d.get((name, impl))
        return median(v) if v else None

    def fmt_us(ns):
        # ns/op -> µs/op with precision that keeps ~3 significant digits.
        us = ns / 1000.0
        if us < 100:
            return f"{us:.1f}"
        return f"{us:,.0f}".replace(",", " ")

    out = []
    w = out.append

    w("# NURL post-quantum crypto peer-comparison\n")
    w(
        f"Generated `{env.get('now','')}` by `bench/run_pq.sh`. "
        "**Do not edit by hand** — the next run overwrites it."
    )
    w("")
    w(
        "Single-core µs/op for the three NIST post-quantum standards — "
        "ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS "
        "group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA "
        "(FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk "
        "throughput they are all built from. NURL is the pure-NURL "
        "stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the "
        "pure-Rust RustCrypto crates. Both sides are portable safe-"
        "language implementations with no hand-written assembly, "
        "measured by the same harness discipline (iteration-calibrated "
        "timed loops, per-op OS randomness, hedged signing, medians "
        f"of {env.get('runs','3')} runs)."
    )
    w("")

    # ── environment ──────────────────────────────────────────────
    w("## Environment\n")
    w("| Item | Value |")
    w("|---|---|")
    w(f"| Host | `{env.get('host','')}` |")
    w(f"| Kernel | `{env.get('kernel','')}` |")
    w(f"| CPU | {env.get('cpu','')} ({env.get('cores','?')} logical cores) |")
    w(f"| Memory | {env.get('mem_kb','?')} KiB |")
    w(f"| Commit | `{env.get('commit','')}` |")
    if env.get("run_url"):
        w(f"| CI run | {env['run_url']} |")
    w(f"| NURL | `{env.get('nurl','')}` |")
    w(f"| Rust | {env.get('rust','')} |")
    w("")
    w("| Implementation | Source |")
    w("|---|---|")
    w("| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |")
    rs = ", ".join(
        f"`{crate} {env.get(key)}`"
        for crate, key in [
            ("ml-kem", "rs_mlkem"),
            ("ml-dsa", "rs_mldsa"),
            ("slh-dsa", "rs_slhdsa"),
            ("shake", "rs_shake"),
        ]
        if env.get(key)
    )
    w(f"| Rust | RustCrypto {rs}, `--release` (opt-level 3, fat LTO) |")
    w("")

    # ── SHAKE throughput ─────────────────────────────────────────
    thr_names = [n for n in order if any((n, i) in thr for i, _ in IMPLS)]
    if thr_names:
        w("## SHAKE128 bulk throughput\n")
        w(
            "Every scheme below spends most of its cycles in Keccak; "
            "this is the one-shot absorb rate over an 8 MB message "
            "(single lane — the multi-lane SIMD Keccak NURL uses inside "
            "SLH-DSA shows up in that table instead)."
        )
        w("")
        w("| | " + " | ".join(disp for _, disp in IMPLS) + " |")
        w("|---|" + "|".join(["---:"] * len(IMPLS)) + "|")
        for name in thr_names:
            vals = {impl: med(thr, name, impl) for impl, _ in IMPLS}
            best = max((v for v in vals.values() if v is not None), default=None)
            cells = []
            for impl, _ in IMPLS:
                v = vals[impl]
                if v is None:
                    cells.append("n/a")
                else:
                    txt = f"{v:.0f} MB/s"
                    cells.append(f"**{txt}**" if v == best else txt)
            w(f"| {name} | " + " | ".join(cells) + " |")
        w("")

    # ── one table per scheme family ──────────────────────────────
    row_names = [n for n in order if any((n, i) in rows for i, _ in IMPLS)]
    used = set()
    for title, prefix in FAMILIES:
        names = [n for n in row_names if n.startswith(prefix)]
        if not names:
            continue
        used.update(names)
        w(f"## {title}\n")
        w("| Operation | NURL µs/op | Rust µs/op | Rust / NURL |")
        w("|---|---:|---:|---:|")
        for name in names:
            a = med(rows, name, "nurl")
            b = med(rows, name, "rust")
            na = "n/a" if a is None else fmt_us(a)
            nb = "n/a" if b is None else fmt_us(b)
            if a is not None and b is not None:
                ratio = f"{b / a:.2f}×"
                if a <= b:
                    na = f"**{na}**"
                else:
                    nb = f"**{nb}**"
            else:
                ratio = "n/a"
            w(f"| {name} | {na} | {nb} | {ratio} |")
        w("")

    leftovers = [n for n in row_names if n not in used]
    if leftovers:
        w("## Other\n")
        w("| Operation | NURL µs/op | Rust µs/op |")
        w("|---|---:|---:|")
        for name in leftovers:
            a = med(rows, name, "nurl")
            b = med(rows, name, "rust")
            w(
                f"| {name} | {'n/a' if a is None else fmt_us(a)} "
                f"| {'n/a' if b is None else fmt_us(b)} |"
            )
        w("")

    w(
        "(Best per row in **bold**. `Rust / NURL` > 1 means NURL is "
        "faster. `n/a` = toolchain absent or the harness failed.)"
    )
    w("")

    # ── notes ────────────────────────────────────────────────────
    w("## Notes\n")
    w(
        "- **Correctness is pinned elsewhere.** Every NURL algorithm "
        "here is byte-exact against NIST ACVP vectors "
        "(`tools/*_acvp_gate.nu`); this report only measures speed."
    )
    w(
        "- **Both sides are portable code.** No hand-written assembly "
        "on either side. NURL's edge in SLH-DSA comes from running four "
        "independent Keccak lanes at a time through `std/hash_sha3x4` "
        "behind the `simd` prefix — same source language, vectorised by "
        "the compiler. The scheme authors' AVX2 implementations are "
        "faster than both sides on the lattice schemes; see the header "
        "of `bench/pq.nu` for that comparison."
    )
    w(
        "- **API-surface caveat (ML-DSA sign).** RustCrypto signs from "
        "a pre-expanded signing key (expansion paid once at keygen); "
        "NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key "
        "and expands per call. The NURL column pays that expansion "
        "inside every sign op, the Rust column does not."
    )
    w(
        "- **Randomness.** Keygen, encaps and hedged signing draw "
        "per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust "
        "`SysRng`), so the syscall cost is in both columns."
    )
    w(
        "- Single core, loopback-free, allocation costs included. "
        "Absolute numbers depend heavily on the host; compare columns "
        "within one run, not across machines."
    )

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
