#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""dwarf_location_census.py — the --g invariant that keeps -O2 inlining sane.

Reads one LLVM IR module nurlc emitted with --g and checks:

  1. every DEFINED function carries a DISubprogram (`define … !dbg !N`);
  2. inside such a function, every call to a function DEFINED in the module
     (an inlining candidate) carries a `!dbg` location.

When either fails, the inliner copies a callee's located instructions
through a location-less call site, cannot build `inlinedAt`, and leaves
them scoped to the wrong subprogram — "!dbg attachment points at wrong
subprogram for function", and clang dies in DwarfDebug::finalizeModuleInfo
at -O2. The memory-model helpers (`__nurl_clone*`, `__nurl_cloneif*`,
`__dropif*`, `drop_glue__*`, `__nurl_ret_own`, `__nurl_hown_*`) are printed
as literal IR by many emitters, which is how both broke.

Usage: dwarf_location_census.py module.ll   (exit 1 with a report on failure)
"""
import re
import sys


def main(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    funcs = re.findall(r'^define [^\n]*?@"?([\w.$]+)"?\(([^\n]*)\{\n(.*?)\n\}', src, re.S | re.M)
    defined = {name for name, _, _ in funcs}
    no_sp, no_loc = [], []
    for name, hdr, body in funcs:
        if "!dbg" not in hdr:
            no_sp.append(name)
            continue
        for line in body.split("\n"):
            m = re.search(r'\bcall [^@]*@"?([\w.$]+)"?\(', line)
            if m and m.group(1) in defined and "!dbg" not in line:
                no_loc.append(f"{name} -> {m.group(1)}")
    if not funcs:
        print(f"census: no function definitions in {path}")
        return 1
    if no_sp or no_loc:
        print(f"census: {len(no_sp)} defined function(s) without a subprogram, "
              f"{len(no_loc)} location-less call(s) to module functions")
        for n in no_sp[:10]:
            print(f"  no subprogram: {n}")
        for c in no_loc[:10]:
            print(f"  no location:   {c}")
        return 1
    print(f"census: {len(funcs)} functions, every one with a subprogram and every module call located")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
