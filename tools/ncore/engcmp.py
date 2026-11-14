# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The engine in nurlc against the reference checker, on one program.

`nurlc --emit-core --engine` prints, after the IR, what the engine built
in the compiler says: `ety` lines (how it reads each type), and later its
summaries and findings.  This reads one such output and says where the
two differ.

  PYTHONUTF8=1 python engcmp.py <file.nu> [...]     (NURLC=<binary>)
  PYTHONUTF8=1 python engcmp.py --list files.txt --jobs 8

Exit status 1 if any program differs.
"""

import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fromnurlc              # noqa: E402
from lower import Types, SCALARS   # noqa: E402
from check import VIEW_TYPES  # noqa: E402

KIND = {"s": 1, "ptr": 2, "opt": 3, "res": 4, "slice": 5, "closure": 6, "String": 7, "vec": 8, "box": 9, "named": 10}
ROOT = os.environ.get("NCORE_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def emit(path):
    nurlc = os.environ.get("NURLC") or os.path.join(ROOT, "build", "nurlc")
    r = subprocess.run([nurlc, "--emit-core", "--engine", path], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=300)
    return r.returncode, r.stdout, r.stderr


def py_types(text):
    """The reference checker's reading of every `ty` line: name -> the
    fields of an `ety` line."""
    rd = fromnurlc.Reader(text)
    prog = rd.prog
    T = Types(prog)
    names = {}
    for name in rd.types:
        names.setdefault(rd.conv(name), name)

    def show(ty):
        if ty is None:
            return "-"
        if ty[0] in SCALARS:
            return "i1" if ty[0] == "b" else "#"
        return names.get(ty, "?")

    out = {}
    for name, info in rd.types.items():
        ty = rd.conv(name)
        k = ty[0]
        kind = 0 if k in SCALARS else KIND[k]
        e1 = e2 = None
        if k in ("ptr", "opt", "slice", "vec", "box"):
            e1 = ty[1]
        elif k == "res":
            e1, e2 = ty[1], ty[2]
        elif k == "named" and ty[1] in prog.handle_elem:
            e1 = prog.handle_elem[ty[1]]
        flags = 0
        if name.startswith("{") or (name.startswith("%") and not name.endswith("*")):
            flags = (1 if info.drops else 0) | (2 if info.clone else 0) | (4 if info.udrop else 0) \
                | (8 if info.share else 0) | (16 if info.tshare else 0)
        if k == "named":
            n = ty[1]
            if n in prog.handle_elem:
                flags |= 32
                if n in prog.shared:
                    flags |= 64
                if n in prog.arcs:
                    flags |= 128
            elif n in prog.enums:
                flags |= 256
            elif n in prog.structs:
                flags |= 512
        if kind == 0:
            # (a number has no table of its own; the flag type is told apart)
            flags = 1024 if k == "b" else 0
        e = T.elem(ty)
        holds = e is not None and (e[0] in VIEW_TYPES or (not T.is_scalar(e) and not T.owning(e)))
        letters = "".join(c if ok else "-" for c, ok in (
            ("n", T.is_scalar(ty)), ("c", T.copyable(ty)), ("o", T.owning(ty)), ("h", T.owns_handle(ty)),
            ("v", T.view_capable(ty)), ("d", T.has_udrop(ty)), ("w", holds)))
        out[name] = (str(kind), show(e1), show(e2), str(flags), letters)
    return out


def compare(path):
    try:
        rc, text, err = emit(path)
    except subprocess.TimeoutExpired:
        return path, ["timeout"]
    if "\nfn\t" not in "\n" + text:
        return path, None                      # nothing lowered (a parse or type error): nothing to compare
    diffs = []
    eng = {}
    for line in text.split("\n"):
        if line.startswith("ety\t"):
            f = line.split("\t")
            eng[f[1]] = tuple(f[2:7])
    try:
        ref = py_types(text)
    except Exception as e:                     # the reader's own limits (an unsupported construct)
        return path, None if "Unsupported" in type(e).__name__ else [f"reader: {type(e).__name__}: {e}"]
    for name, want in ref.items():
        got = eng.get(name)
        if got is None:
            diffs.append(f"type {name}: the engine did not list it")
        elif got != want:
            diffs.append(f"type {name}: engine {got}  reference {want}")
    return path, diffs


def main(argv):
    jobs = 1
    files = []
    i = 0
    while i < len(argv):
        if argv[i] == "--jobs":
            jobs = int(argv[i + 1]); i += 2
        elif argv[i] == "--list":
            files += [l.strip() for l in open(argv[i + 1], encoding="utf-8") if l.strip()]; i += 2
        else:
            files.append(argv[i]); i += 1
    if not files:
        print(__doc__)
        return 2
    bad = same = skipped = 0
    shown = 0
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        for path, diffs in ex.map(compare, files):
            if diffs is None:
                skipped += 1
            elif diffs:
                bad += 1
                if shown < 25:
                    shown += 1
                    print(os.path.basename(path))
                    for d in diffs[:6]:
                        print("   ", d)
            else:
                same += 1
    print(f"engcmp: {same} same, {bad} differ, {skipped} not compared")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
