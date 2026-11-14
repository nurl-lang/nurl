# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""One program through the reference checker, shown: its verdict, its
errors and the summaries of its functions; with `--trace FN`, the state
after each statement of that function.

  PYTHONUTF8=1 python show.py <probe.nu> [function ...]
  PYTHONUTF8=1 python show.py --trace main <probe.nu>

(NURLC=<binary>, NCORE_CACHE=<dir> as for run.py; NCORE_TRACE=<binding>
says which effect ends a loan on that binding; NCORE_SHOW_VARS=a,b
limits a trace to those bindings.)
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check                  # noqa: E402
import run                    # noqa: E402

QUIET = ("vec_", "string_", "nurl_", "str_", "option_", "opt_", "res_", "mem_", "slice_")


def main(argv):
    trace = None
    if argv and argv[0] == "--trace":
        trace, argv = argv[1], argv[2:]
    if not argv:
        print(__doc__)
        return 2
    path, want = argv[0], argv[1:]
    if not os.path.exists(path):
        path = os.path.join(run.HOLES, path)
    if trace:
        inner = check.FnCheck.stmt
        only = set(filter(None, os.environ.get("NCORE_SHOW_VARS", "").split(",")))

        def stmt(self, st, s):
            out = inner(self, st, s)
            if self.final and self.fn.name == trace:
                vals = "bottom" if out is None or out.bottom else {
                    self.vname(v): a for v, a in out.vals.items()
                    if a.own != "N" and (not only or self.vname(v) in only)}
                print(str(s)[:110])
                print("      ", str(vals)[:700 if not only else 4000])
            return out
        check.FnCheck.stmt = stmt
    verdict, errors, summ = run.verdict_nurlc(path)
    print(verdict)
    for e in errors:
        print("  ", e)
    for name, sm in summ.items():
        if (want and name in want) or (not want and not name.startswith(QUIET)):
            print(name, {k: v for k, v in sm.items() if v and k != "modes"})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
