#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  leak_triage.py — group the corpus's leaks so they can be pulled
#  one cause at a time.
#
#      ./build.sh --san --no-tests
#      LSAN_DETECT_LEAKS=1 ./compiler/tests/run_san_tests.sh
#      python3 tools/fuzz/leak_triage.py
#
#  run_san_tests.sh sets detect_leaks=0 by default — some corpus
#  programs omit cleanup to isolate the behaviour under test — so the
#  leak behaviour of most of the corpus goes unmeasured. With detection
#  on it reports around ninety leaking programs, which is a list nobody
#  reads. This groups them by the function that made the leaked
#  allocation, which is what turns the list into a handful of causes.
#
#  The grouping is a starting point, not a verdict. Where a value is
#  MADE says nothing about whose job it is to free it: `bytes_from_hex`
#  hands its Vec to the caller inside a Result, so its leaks are the
#  caller's omission, while a temporary passed to a function whose
#  parameter is classified as escaping cannot be freed by anyone. The
#  question that separates them is "could the program have freed it?" —
#  answer it by writing the same call with the free present and seeing
#  whether the leak goes away.
#
#  Reads the stderr logs the sanitized runner already wrote; it does not
#  run anything itself.
# ============================================================
import argparse
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_LOGS = os.path.join(ROOT, "build", "tests-san", "logs")

ALLOCATORS = {
    "malloc", "calloc", "realloc", "nurl_malloc", "nurl_zalloc",
    "nurl_alloc", "nurl_realloc", "nurl__xmalloc", "operator",
}


def first_real_frame(report):
    """The first frame under the allocator wrappers — the function that
    actually asked for the memory."""
    for name in re.findall(r"\bin ([A-Za-z_][A-Za-z0-9_]*)", report):
        if name not in ALLOCATORS:
            return name
    return "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", default=DEFAULT_LOGS,
                    help="directory of <test>.stderr files from run_san_tests.sh")
    args = ap.parse_args()

    if not os.path.isdir(args.logs):
        print(f"leak_triage: no logs at {args.logs} — run the sanitized corpus "
              f"with LSAN_DETECT_LEAKS=1 first", file=sys.stderr)
        return 2

    by_frame = defaultdict(list)
    sizes = {}
    for entry in sorted(os.listdir(args.logs)):
        if not entry.endswith(".stderr"):
            continue
        path = os.path.join(args.logs, entry)
        try:
            text = open(path, errors="replace").read()
        except OSError:
            continue
        if "LeakSanitizer: detected memory leaks" not in text:
            continue
        test = entry[: -len(".stderr")]
        by_frame[first_real_frame(text)].append(test)
        m = re.search(r"SUMMARY: AddressSanitizer: (\d+) byte", text)
        sizes[test] = int(m.group(1)) if m else 0

    total = sum(len(v) for v in by_frame.values())
    if total == 0:
        print("leak_triage: no leaking programs in these logs — either the "
              "corpus is clean or leak detection was off (LSAN_DETECT_LEAKS=1)")
        return 0

    print(f"{total} leaking program(s), grouped by the function that allocated:\n")
    for frame, tests in sorted(by_frame.items(), key=lambda kv: -len(kv[1])):
        worst = max(tests, key=lambda t: sizes.get(t, 0))
        print(f"  {len(tests):3d}  {frame}")
        print(f"       {', '.join(sorted(tests)[:6])}"
              f"{' …' if len(tests) > 6 else ''}")
        print(f"       largest: {worst} ({sizes.get(worst, 0)} bytes)")
    print("\nA group is one hypothesis. Test it by writing the same call with "
          "the free present:\n  a leak that goes away was the program's to "
          "reclaim; one that stays is the compiler's.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
