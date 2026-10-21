#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_doc_examples.py — the analysis half of check_doc_examples.sh.
#
#  Runnable directly:
#     python3 tools/check_doc_examples.py [--jobs N] [--verbose] [FILE.md ...]
# ============================================================
"""Every NURL example in the docs compiles — or fails the way it says.

Readers and agents copy documentation examples verbatim. MEMORY.md §2.11
showed a closure-capture example that died with "unknown generic type
( Vec … )" long before the use-after-move it was there to demonstrate,
because the block had no `$ stdlib/core/vec.nu` import; nothing compiled
it, so nothing noticed.

This pass extracts every fenced block tagged `nurl`, turns it into a
compilation unit and runs `nurlc --check` on it (the full frontend —
parse, imports, typecheck, borrow checker — with no IR written), all
blocks in parallel.

Fence info strings
------------------
    ```nurl                          must compile
    ```nurl expect-error="TEXT"      must be REJECTED, and every error
                                     located in the block must contain
                                     one of the TEXTs (repeatable); each
                                     TEXT must be matched by an error on
                                     a line of THIS block
    ```nurl expect-warning="TEXT"    must compile and warn with TEXT
    ```nurl flags="--strict-borrowck"  extra nurlc flags
    ```nurl continue                 the previous nurl block of the same
                                     file is prepended (a walk-through
                                     split across prose)
    ```nurl ignore="REASON"          not compiled; the reason is required
                                     (grammar sketches, `…` elisions)

A `<!-- doctest-prelude ... -->` HTML comment ending on the line right
before a fence is prepended to that block only. It renders as nothing,
so it holds context the prose has already introduced (a struct the
section defined earlier) without repeating it in every snippet.

Wrapping
--------
A block that defines `@ main` is compiled as written. Otherwise its
top-level items — every line up to the end of the last declaration
(`@`, `pub`/`unsafe`/`inline`/`simd`/`raw` `@`, `:` type, `: |`, `%`,
`&` FFI), globals between them included — stay at the top level, `$`
imports are hoisted, and the statements after them become the body of
`@ main → i { … ^ 0 }`. Nothing is imported implicitly: an example has
to name its imports, so a reader who copies it gets a program that
resolves.

Scope
-----
In docs/**/*.md and README.md (STRICT) every fence must name a
language: an untagged fence is an error, so a NURL example cannot opt
out by omission — prose output is `text`, a shell session `sh`.
Package READMEs (packages/*/README.md) and examples/README.md have
their `nurl` blocks compiled but untagged fences tolerated.

Output is `file:line: …` per failing block, with the compiler's
diagnostics mapped back to the markdown line they came from.
"""
import concurrent.futures
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STRICT_GLOBS = ["docs/**/*.md", "README.md"]
LOOSE_GLOBS = ["packages/*/README.md", "examples/README.md"]

FENCE_OPEN = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
ATTR = re.compile(r'([A-Za-z][\w-]*)(?:=(?:"([^"]*)"|(\S+)))?')
PRELUDE_OPEN = re.compile(r"^\s*<!--\s*doctest-prelude\b(.*)$")

# A line (at the block's own indentation) that starts a top-level item.
DECL = re.compile(
    r"^(?:pub\s+)?(?:(?:unsafe|inline|simd|raw|export)\s+)*@\s"  # function
    r"|^(?:pub\s+)?:\s*\|"                                        # enum
    r"|^(?:pub\s+)?:\s*[A-Za-z_]\w*\s*(?:\[[^\]]*\]\s*)?\{"       # struct
    r"|^%\s"                                                      # trait / impl
    r"|^&\s*`"                                                    # FFI
)
IMPORT = re.compile(r"^\$\s")
MAIN = re.compile(r"^(?:pub\s+)?(?:unsafe\s+)?@\s+main\b")
LOC = re.compile(r"^(.*?):(\d+):(\d+): (error|warning): (.*)$")

KNOWN_ATTRS = {"expect-error", "expect-warning", "flags", "continue", "ignore"}


class Block:
    def __init__(self, path, line, info, lines, prelude, prelude_line):
        self.path = path            # repo-relative markdown path
        self.line = line            # 1-based line of the opening fence
        self.info = info
        self.lines = lines          # dedented block text, one per line
        self.prelude = prelude      # list of lines, or []
        self.prelude_line = prelude_line
        self.attrs = {}
        self.expect_errors = []
        self.expect_warnings = []
        self.bad_attrs = []
        for m in ATTR.finditer(info):
            key = m.group(1)
            val = m.group(2) if m.group(2) is not None else m.group(3)
            if key == "expect-error":
                self.expect_errors.append(val or "")
            elif key == "expect-warning":
                self.expect_warnings.append(val or "")
            elif key in KNOWN_ATTRS:
                self.attrs[key] = val if val is not None else ""
            else:
                self.bad_attrs.append(key)
        self.prev = None            # previous nurl block of the same file

    def where(self):
        return f"{self.path}:{self.line}"


def dedent(lines):
    width = min((len(l) - len(l.lstrip()) for l in lines if l.strip()), default=0)
    return [l[width:] for l in lines]


def scan(path, strict):
    """Yield the file's nurl blocks; collect untagged fences in STRICT files."""
    text = open(os.path.join(ROOT, path), encoding="utf-8").read().split("\n")
    blocks, problems = [], []
    i = 0
    prev = None
    while i < len(text):
        m = FENCE_OPEN.match(text[i])
        if not m:
            i += 1
            continue
        fence, info = m.group(2), m.group(3).strip()
        close = re.compile(r"^\s*" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$")
        j = i + 1
        while j < len(text) and not close.match(text[j]):
            j += 1
        lang = info.split()[0] if info else ""
        if lang == "nurl":
            prelude, pline = [], 0
            k = i - 1
            if k >= 0 and text[k].strip().endswith("-->"):
                s = k
                while s >= 0 and not PRELUDE_OPEN.match(text[s]):
                    if "<!--" in text[s] and s != k:
                        s = -1
                        break
                    s -= 1
                if s >= 0:
                    body = text[s:k + 1]
                    body[0] = PRELUDE_OPEN.match(body[0]).group(1)
                    body[-1] = body[-1].rstrip()[:-3]
                    prelude, pline = body, s + 1
            b = Block(path, i + 1, info[4:].strip(), dedent(text[i + 1:j]), prelude, pline)
            b.prev = prev
            prev = b
            blocks.append(b)
        elif not info and strict:
            problems.append(f"{path}:{i + 1}: untagged fence — name its language "
                            "(`nurl` to compile it, `text` for output or prose, `sh`, …)")
        i = j + 1
    return blocks, problems


def strip_code(line):
    """The line without `strings` and // comments, for brace counting."""
    out, in_str, k = [], False, 0
    while k < len(line):
        c = line[k]
        if c == "`":
            in_str = not in_str
        elif not in_str:
            if line.startswith("//", k):
                break
            out.append(c)
        k += 1
    return "".join(out)


def units(block):
    """(source lines, origin) pairs for this block's whole chain:
    origin is (md line) for a line of a doc, or None for wrapper text."""
    chain = []
    b = block
    while b is not None:
        chain.append(b)
        b = b.prev if "continue" in b.attrs else None
    chain.reverse()
    out = []
    for b in chain:
        for n, l in enumerate(dedent(b.prelude) if b.prelude else []):
            out.append((l, (b, b.prelude_line + n)))
        for n, l in enumerate(b.lines):
            out.append((l, (b, b.line + 1 + n)))
    return out


def wrap(pairs):
    """Split into top-level items and main-body statements."""
    if any(MAIN.match(l) for l, _ in pairs):
        return pairs
    imports = [(l, o) for l, o in pairs if IMPORT.match(l)]
    rest = [(l, o) for l, o in pairs if not IMPORT.match(l)]
    # End (exclusive) of the last top-level declaration.
    split, depth, in_decl = 0, 0, False
    for idx, (l, _) in enumerate(rest):
        if depth == 0 and DECL.match(l):
            in_decl = True
        code = strip_code(l)
        depth += code.count("{") - code.count("}")
        if in_decl and depth <= 0:
            split, depth, in_decl = idx + 1, 0, False
    top, body = rest[:split], rest[split:]
    if not any(l.strip() for l, _ in body):
        return imports + top
    stmts = [l for l, _ in body if l.strip() and not l.strip().startswith("//")]
    tail = [] if stmts and stmts[-1].lstrip().startswith("^") else [("    ^ 0", None)]
    return (imports + top + [("@ main → i {", None)]
            + [("    " + l, o) for l, o in body] + tail + [("}", None)])


def check(block, nurlc, tmpdir, cwd):
    flags = block.attrs.get("flags", "").split()
    pairs = wrap(units(block))
    name = re.sub(r"[^\w]", "_", block.path) + f"_{block.line}.nu"
    src = os.path.join(tmpdir, name)
    with open(src, "w", encoding="utf-8") as f:
        f.write("\n".join(l for l, _ in pairs) + "\n")
    proc = subprocess.run([nurlc, "--check", *flags, src], cwd=cwd,
                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                          text=True, errors="replace", timeout=120)
    diags, mapped = [], []
    for raw in proc.stderr.splitlines():
        m = LOC.match(raw)
        if m and os.path.abspath(os.path.join(cwd, m.group(1))) == src:
            ln = int(m.group(2))
            origin = pairs[ln - 1][1] if 0 < ln <= len(pairs) else None
            where = (f"{origin[0].path}:{origin[1]}" if origin
                     else f"{block.path}:{block.line} (wrapper line {ln})")
            diags.append((m.group(4), m.group(5), origin))
            mapped.append(f"{where}:{m.group(3)}: {m.group(4)}: {m.group(5)}")
        elif m:
            diags.append((m.group(4), m.group(5), "elsewhere"))
            mapped.append(raw)
        else:
            mapped.append(raw)
    return proc.returncode, diags, mapped, pairs


def judge(block, rc, diags):
    """None when the block behaved as annotated, else the reason."""
    errors = [d for d in diags if d[0] == "error"]
    if block.expect_errors:
        if rc == 0:
            return "expected a compile error, but the block compiled"
        for msg_kind, msg, origin in errors:
            if not any(e in msg for e in block.expect_errors):
                return "an error the annotation does not expect"
        for e in block.expect_errors:
            if not any(e in msg and origin not in (None, "elsewhere")
                       and origin[0] is block for _, msg, origin in errors):
                return f'no error in this block contains "{e}"'
        return None
    if rc != 0:
        return "does not compile"
    for w in block.expect_warnings:
        if not any(d[0] == "warning" and w in d[1] for d in diags):
            return f'no warning contains "{w}"'
    return None


def make_cwd():
    """A scratch root where `stdlib/…`, `packages/…` and `deps/<pkg>/…`
    all resolve, so a package README's `$ \\`deps/http/src/http.nu\\``
    finds the in-tree package the way an installed one would be found."""
    d = tempfile.mkdtemp(prefix="nurl-doctest-")
    for name in ("stdlib", "packages", "examples", "compiler"):
        os.symlink(os.path.join(ROOT, name), os.path.join(d, name))
    os.mkdir(os.path.join(d, "deps"))
    for pkg in sorted(os.listdir(os.path.join(ROOT, "packages"))):
        if os.path.isdir(os.path.join(ROOT, "packages", pkg)):
            os.symlink(os.path.join(ROOT, "packages", pkg), os.path.join(d, "deps", pkg))
    return d


def main(argv):
    jobs = min(4, os.cpu_count() or 1)
    verbose = False
    files = []
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("-j", "--jobs"):
            jobs = int(argv[k + 1]); k += 2; continue
        if a in ("-v", "--verbose"):
            verbose = True
        else:
            files.append(os.path.relpath(os.path.abspath(a), ROOT))
        k += 1
    jobs = int(os.environ.get("NURL_DOCTEST_JOBS", jobs))
    nurlc = os.path.join(ROOT, "build", "nurlc")
    if not os.access(nurlc, os.X_OK):
        print("error: build/nurlc not built — run ./build.sh first", file=sys.stderr)
        return 2

    def expand(globs):
        out = []
        for g in globs:
            out += sorted(glob.glob(os.path.join(ROOT, g), recursive=True))
        return [os.path.relpath(p, ROOT) for p in out]
    strict = set(expand(STRICT_GLOBS))
    targets = files or sorted(strict | set(expand(LOOSE_GLOBS)))

    blocks, problems = [], []
    for path in targets:
        bs, ps = scan(path, path in strict)
        blocks += bs
        problems += ps
    for b in blocks:
        if b.bad_attrs:
            problems.append(f"{b.where()}: unknown fence attribute(s) {', '.join(b.bad_attrs)} "
                            f"(known: {', '.join(sorted(KNOWN_ATTRS))})")
        if "ignore" in b.attrs and not b.attrs["ignore"].strip():
            problems.append(f'{b.where()}: `ignore` needs a reason: ignore="…"')
        if "continue" in b.attrs and b.prev is None:
            problems.append(f"{b.where()}: `continue` but no earlier nurl block in the file")

    run = [b for b in blocks if "ignore" not in b.attrs]
    ignored = len(blocks) - len(run)
    tmpdir = tempfile.mkdtemp(prefix="nurl-doctest-src-")
    cwd = make_cwd()
    failures = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            futs = {ex.submit(check, b, nurlc, tmpdir, cwd): b for b in run}
            for fut in concurrent.futures.as_completed(futs):
                b = futs[fut]
                rc, diags, mapped, pairs = fut.result()
                why = judge(b, rc, diags)
                if why:
                    failures.append((b, why, mapped, pairs))
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        shutil.rmtree(cwd, ignore_errors=True)

    failures.sort(key=lambda f: (f[0].path, f[0].line))
    for p in problems:
        print(p)
    for b, why, mapped, pairs in failures:
        print(f"{b.where()}: FAIL — {why}  [```nurl {b.info}]".rstrip())
        for l in mapped:
            print(f"    {l}")
        if verbose:
            print("    ── compiled as ──")
            for n, (l, _) in enumerate(pairs, 1):
                print(f"    {n:4} | {l}")
    passed = len(run) - len(failures)
    print(f"\ndoc examples: PASS {passed} · FAIL {len(failures)} · IGNORED {ignored}"
          f" · fence problems {len(problems)}  ({len(targets)} files)")
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
