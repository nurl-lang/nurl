#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# bench/cpu_env.py — which CPU a benchmark ran on: its vendor, the flags a
# kernel is chosen by, and the family those two decide.
#
#   cpu_env.py vendor     the vendor (x86 `vendor_id`, AArch64 `CPU implementer`)
#   cpu_env.py flags      the dispatch-relevant flags present, in a fixed order
#   cpu_env.py family     the family id, e.g. amd-avx2-vaes-sha-adx
#
# One place for it, because every runner-measured report needs the same
# answer: the GitHub runner pool hands out AMD Zen 3, AMD Zen 4/5 and Intel
# Ice Lake machines, and a ratio between two implementations can flip with
# the family, not with the code (Agora #112). The TLS bench records its runs
# per family with it (run_tls.sh, gen_tls_results.py); the HTTP torture
# harness writes it into its report header (Agora #120).
#
# The family is decided by the flags, never by the model string: the
# vendor, the widest vector ISA (avx2 / avx512 / avx512ifma), then the
# extensions a crypto dispatch picks a kernel by (vaes, sha, adx).
import re
import sys

# Every flag a NURL or aws-lc kernel is chosen by. x86 reports them in
# `flags`, AArch64 in `Features`.
FLAGS = ("aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw "
         "avx512ifma avx512vbmi asimd pmull sha2 sha512 sve sve2").split()


def read_cpuinfo(path="/proc/cpuinfo"):
    """(vendor, the FLAGS present in FLAGS' order) of the first CPU listed."""
    vendor, have = "", set()
    try:
        with open(path) as f:
            for line in f:
                key, _, val = line.partition(":")
                key = key.strip()
                if not vendor and key in ("vendor_id", "CPU implementer"):
                    vendor = val.strip()
                elif not have and key in ("flags", "Features"):
                    have = set(val.split())
                if vendor and have:
                    break
    except OSError:
        pass
    return vendor, [f for f in FLAGS if f in have]


def family_of(env):
    """The CPU family a run belongs to, from env's cpu_vendor and cpu_flags alone."""
    vendor_raw = env.get("cpu_vendor", "").strip()
    vendor = {"AuthenticAMD": "amd", "GenuineIntel": "intel"}.get(vendor_raw)
    if vendor is None:
        vendor = re.sub(r"[^a-z0-9]+", "", vendor_raw.lower()) or "unknown"
    flags = set(env.get("cpu_flags", "").split())
    if {"avx512f", "avx512ifma"} <= flags:
        vec = "avx512ifma"
    elif "avx512f" in flags:
        vec = "avx512"
    elif "avx2" in flags:
        vec = "avx2"
    elif "sve" in flags:
        vec = "sve"
    elif "asimd" in flags:
        vec = "neon"
    else:
        vec = "base"
    parts = [vendor, vec]
    for flag, tag in (("vaes", "vaes"), ("sha_ni", "sha"), ("sha2", "sha"), ("adx", "adx")):
        if flag in flags and tag not in parts:
            parts.append(tag)
    return "-".join(parts)


def main(argv):
    if len(argv) != 2 or argv[1] not in ("vendor", "flags", "family"):
        sys.stderr.write("usage: cpu_env.py vendor|flags|family\n")
        return 2
    vendor, flags = read_cpuinfo()
    if argv[1] == "vendor":
        print(vendor)
    elif argv[1] == "flags":
        print(" ".join(flags))
    else:
        print(family_of({"cpu_vendor": vendor, "cpu_flags": " ".join(flags)}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
