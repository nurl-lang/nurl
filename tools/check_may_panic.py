#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Every runtime entry that can start a panic is one nurlc knows can.

nurlc's journal elision (compiler/nurlc.nu, the "Journal elision" section)
drops the panic-journal registration of a temporary released in the same
block when nothing in between can panic. Which external callees can is
`__mp_runtime_panics`, a list kept by hand. A C entry that calls
nurl_panic but is missing from it makes nurlc elide the registrations
around its calls, and a panic from it under `recover` leaks the
temporaries live there: a gap in what A2.no_leak_panic promises for
compiled code. The default is the unsafe direction, so the list is held
against the runtime here (agora #537): stdlib/runtime.c is compiled to
LLVM IR, every exported `nurl_*` function whose direct calls reach a panic
(nurl_panic, nurl_panic_index, a longjmp) is collected, and nurlc is asked
(`--may-panic=`) about each. One it answers F for fails the check.

Calls through a pointer (a drop / clone thunk, a closure) are not followed:
nurlc answers those by the call site (a thunk argument, a fiber switch),
not by the callee's name.

    python3 tools/check_may_panic.py [build/nurlc]
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTS = {"nurl_panic", "nurl_panic_index", "longjmp", "_longjmp", "siglongjmp", "__longjmp_chk"}
DEFINE = re.compile(r'^define\s+([^@]*)@"?([\w.$]+)"?\(')
CALL = re.compile(r'\bcall\b[^@]*@"?([\w.$]+)"?\(')


def may_panic(ir_text):
    """The exported nurl_* functions of `ir_text` whose direct calls reach a
    panic root, each with one call chain that shows it."""
    calls, linkage, cur = collections.defaultdict(set), {}, None
    for line in ir_text.splitlines():
        m = DEFINE.match(line)
        if m:
            cur = m.group(2)
            linkage[cur] = m.group(1)
            continue
        if line.startswith("}"):
            cur = None
        elif cur:
            calls[cur].update(CALL.findall(line))
    callers = collections.defaultdict(set)
    for f, cs in calls.items():
        for c in cs:
            callers[c].add(f)
    via = {r: [r] for r in ROOTS}
    todo = list(ROOTS)
    while todo:
        x = todo.pop()
        for f in callers[x]:
            if f not in via:
                via[f] = [f] + via[x]
                todo.append(f)
    return {f: via[f] for f in via
            if f in linkage and f.startswith("nurl_")
            and "internal" not in linkage[f] and "private" not in linkage[f]}


def runtime_ir():
    cc = os.environ.get("CLANG", "clang")
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "runtime.ll")
        subprocess.run([cc, "-O0", "-S", "-emit-llvm", "-w", "-o", out,
                        os.path.join(ROOT, "stdlib", "runtime.c")], check=True, cwd=ROOT)
        with open(out) as fh:
            return fh.read()


def ask_nurlc(nurlc, names):
    r = subprocess.run([nurlc, "--may-panic=" + ",".join(sorted(names))],
                       check=True, capture_output=True, text=True)
    return dict(line.split(" ", 1) for line in r.stdout.splitlines() if " " in line)


def main(argv):
    nurlc = argv[1] if len(argv) > 1 else os.path.join(ROOT, "build", "nurlc")
    found = may_panic(runtime_ir())
    answers = ask_nurlc(nurlc, found)
    missed = sorted(f for f in found if answers.get(f) == "F")
    unanswered = sorted(f for f in found if f not in answers)
    for f in missed:
        print("ERROR: %s can start a panic (%s), but nurlc's journal elision takes it for one "
              "that cannot: add it to __mp_runtime_panics (compiler/nurlc.nu)"
              % (f, " -> ".join(found[f])), file=sys.stderr)
    for f in unanswered:
        print("ERROR: nurlc gave no answer for %s" % f, file=sys.stderr)
    if missed or unanswered:
        return 1
    print("ok: %d runtime entries can start a panic; nurlc knows each one" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
