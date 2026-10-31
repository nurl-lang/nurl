#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_doc_examples.py — the analysis half of check_doc_examples.sh.
#
#  Runnable directly:
#     python3 tools/check_doc_examples.py [--jobs N] [--verbose] [--timings] [FILE.md ...]
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
    ```nurl unsafe                   the statements run in `unsafe @ main`
                                     (a snippet of raw-memory or FFI code)
    ```nurl params="T a U b"         the statements are the body of
                                     `@ __doctest_snippet T a U b → v`
                                     instead of `main`: the snippet's
                                     free names, of any type, with
                                     nothing to construct
    ```nurl continue                 the previous nurl block of the same
                                     file is prepended (a walk-through
                                     split across prose)
    ```nurl ignore="REASON"          not compiled; the reason is required
                                     (grammar sketches, `…` elisions)

A `<!-- doctest-prelude ... -->` HTML comment ending on the line right
before a fence is prepended to that block only. It renders as nothing,
so it holds context the prose has already introduced (a struct the
section defined earlier) without repeating it in every snippet. A
`<!-- doctest-file-prelude ... -->` anywhere in the file is prepended to
every snippet of that file that does not define `main` itself (a
package README's import and the handle its fragments all use).

Wrapping
--------
A block that defines `@ main` is compiled as written. Otherwise each of
its segments (the file prelude, the block prelude, the block itself, in
that order) is split at the end of its last declaration (`@`,
`pub`/`unsafe`/`inline`/`simd`/`raw` `@`, `:` type, `: |`, `%`, `&`
FFI): everything up to there — globals between declarations included —
stays at the top level, `$` imports are hoisted, and the statements
after it become the body of `@ main → i { … ^ 0 }`. Nothing is imported
implicitly: an example has to name its imports, so a reader who copies
it gets a program that resolves.

Scope
-----
In docs/*.md, docs/stdlib/*.md and README.md (STRICT) every fence must
name a language: an untagged fence is an error, so a NURL example
cannot opt out by omission — prose output is `text`, a shell session
`sh`. Package READMEs (packages/*/README.md) and examples/README.md
have their `nurl` blocks compiled but untagged fences tolerated.
docs/dev/ (working notes that quote historical, since-fixed programs)
is not checked.

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
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STRICT_GLOBS = ["docs/*.md", "docs/stdlib/*.md", "README.md"]
LOOSE_GLOBS = ["packages/*/README.md", "examples/README.md"]

FENCE_OPEN = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
ATTR = re.compile(r'([A-Za-z][\w-]*)(?:=(?:"([^"]*)"|(\S+)))?')
PRELUDE_OPEN = re.compile(r"^\s*<!--\s*doctest-prelude\b(.*)$")
FILE_PRELUDE_OPEN = re.compile(r"^\s*<!--\s*doctest-file-prelude\b(.*)$")

# A line (at the block's own indentation) that starts a top-level item.
DECL = re.compile(
    r"^(?:pub\s+)?(?:(?:unsafe|inline|simd(?:\s+v4)?|raw|export)\s+)*@\s"  # function
    r"|^(?:pub\s+)?:\s*\|"                                        # enum
    r"|^(?:pub\s+)?:\s*[A-Za-z_]\w*\s*(?:\[[^\]]*\]\s*)?\{"       # struct
    r"|^%\s"                                                      # trait / impl
    r"|^&\s*`"                                                    # FFI
)
IMPORT = re.compile(r"^\$\s")
MAIN = re.compile(r"^(?:pub\s+)?(?:unsafe\s+)?@\s+main\b")
# `file:line:col: error: …` — every diagnostic that names a file names a
# column too, deferred whole-program checks included (die_file_pos re-reads
# the line). `file:line: error: …` is the shape they used to print: it is
# reported, never mapped, so a regression to it fails the block.
LOC = re.compile(r"^(.*?):(\d+)(:\d+): (error|warning): (.*)$")
NO_COL = re.compile(r"^(.*?\.nu):(\d+): (error|warning): (.*)$")

NO_SENTINEL = "is required but no build-time sentinel"
KNOWN_ATTRS = {"expect-error", "expect-warning", "flags", "continue", "ignore", "unsafe", "params"}


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
        self.file_prelude = []      # [(line, md line)] shared by the file

    def where(self):
        return f"{self.path}:{self.line}"


def dedent(lines):
    width = min((len(l) - len(l.lstrip()) for l in lines if l.strip()), default=0)
    return [l[width:] for l in lines]


def scan(path, strict):
    """Yield the file's nurl blocks; collect untagged fences in STRICT files."""
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        text = f.read().split("\n")
    blocks, problems = [], []
    file_prelude = []
    for k, l in enumerate(text):
        m = FILE_PRELUDE_OPEN.match(l)
        if m:
            first = m.group(1)
            e = k
            while e < len(text) and "-->" not in text[e]:
                e += 1
            body = [first] + text[k + 1:e + 1] if e > k else [first]
            body[-1] = body[-1].split("-->")[0]
            file_prelude += [(t, k + 1 + n) for n, t in enumerate(body)]
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
        if fence[0] == "`" and "`" in info:
            # CommonMark: such a line is not a fence at all, so the block
            # and everything after it renders wrong.
            problems.append(f"{path}:{i + 1}: a backtick in the info string of a ``` fence "
                            "breaks the fence — leave it out of the annotation")
        if lang == "nurl":
            prelude, pline = [], 0
            k = i - 1
            if k >= 0 and text[k].strip().endswith("-->"):
                s = k
                while s >= 0 and not PRELUDE_OPEN.match(text[s]):
                    if "<!--" in text[s]:      # some other comment
                        s = -1
                        break
                    s -= 1
                if s >= 0:
                    body = text[s:k + 1]
                    body[0] = PRELUDE_OPEN.match(body[0]).group(1)
                    body[-1] = body[-1].rstrip()[:-3]
                    prelude, pline = body, s + 1
            b = Block(path, i + 1, info[4:].strip(), dedent(text[i + 1:j]), prelude, pline)
            b.file_prelude = file_prelude
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
    """The block's whole chain as segments — the file prelude, then each
    block's own prelude and lines — of (source line, origin) pairs:
    origin is (block, md line), or None for wrapper text."""
    chain = []
    b = block
    while b is not None:
        chain.append(b)
        b = b.prev if "continue" in b.attrs else None
    chain.reverse()
    segs = []
    # The file's shared context is for snippets; a whole program (one
    # that defines `main`) brings its own.
    fp = chain[0].file_prelude
    if fp and not any(MAIN.match(l) for b in chain for l in b.lines):
        segs.append([(l, (chain[0], n)) for l, n in zip(dedent([t for t, _ in fp]),
                                                       [n for _, n in fp])])
    for b in chain:
        if b.prelude:
            segs.append([(l, (b, b.prelude_line + n)) for n, l in enumerate(dedent(b.prelude))])
        segs.append([(l, (b, b.line + 1 + n)) for n, l in enumerate(b.lines)])
    return segs


def split_segment(seg):
    """(top-level items, statements) of one segment: every line up to the
    end of its last declaration is top-level (globals between
    declarations included), the rest is statements."""
    split, depth, in_decl = 0, 0, False
    for idx, (l, _) in enumerate(seg):
        if depth == 0 and DECL.match(l):
            in_decl = True
        code = strip_code(l)
        depth += code.count("{") - code.count("}")
        if in_decl and depth <= 0:
            split, depth, in_decl = idx + 1, 0, False
    return seg[:split], seg[split:]


def wrap(segs, unsafe=False, params=None):
    """One compilation unit: imports hoisted, each segment's top-level
    items next, and the statements of all segments, in order, as the
    body of `main`."""
    pairs = [p for seg in segs for p in seg]
    if any(MAIN.match(l) for l, _ in pairs):
        return pairs
    imports = [(l, o) for l, o in pairs if IMPORT.match(l)]
    top, body = [], []
    for seg in segs:
        t, b = split_segment([(l, o) for l, o in seg if not IMPORT.match(l)])
        top += t
        body += b
    if not any(l.strip() for l, _ in body):
        return imports + top
    stmts = [l for l, _ in body if l.strip() and not l.strip().startswith("//")]
    tail = [] if stmts and stmts[-1].lstrip().startswith("^") else [("    ^ 0", None)]
    head = "@ main → i {"
    if params is not None:
        # The snippet's free names are the parameters of a function of
        # its own: a value of any type, with nothing to construct.
        head, tail = f"@ __doctest_snippet {params} → v {{", []
    if unsafe:
        head = "unsafe " + head
    return (imports + top + [(head, None)]
            + [("    " + l, o) for l, o in body] + tail + [("}", None)])


def check(block, nurlc, tmpdir, cwd):
    flags = block.attrs.get("flags", "").split()
    pairs = wrap(units(block), "unsafe" in block.attrs, block.attrs.get("params"))
    name = re.sub(r"[^\w]", "_", block.path) + f"_{block.line}.nu"
    src = os.path.join(tmpdir, name)
    with open(src, "w", encoding="utf-8") as f:
        f.write("\n".join(l for l, _ in pairs) + "\n")
    t0 = time.monotonic()
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
            mapped.append(f"{where}{m.group(3) or ''}: {m.group(4)}: {m.group(5)}")
        elif m:
            diags.append((m.group(4), m.group(5), "elsewhere"))
            mapped.append(raw)
        else:
            n = NO_COL.match(raw)
            if n:
                diags.append((n.group(3), n.group(4), "no-column"))
            mapped.append(raw)
    return proc.returncode, diags, mapped, pairs, time.monotonic() - t0


def judge(block, rc, diags):
    """None when the block behaved as annotated, else the reason."""
    if any(origin == "no-column" for _, _, origin in diags):
        return "a diagnostic without a column ('file:line: …') — every located diagnostic prints file:line:col"
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
    # Under the name its manifest gives it, which is what `deps/<name>/`
    # spells (packages/gRPC is the package `grpc`).
    for pkg in sorted(os.listdir(os.path.join(ROOT, "packages"))):
        here = os.path.join(ROOT, "packages", pkg)
        name = pkg
        try:
            with open(os.path.join(here, "nurl.toml"), encoding="utf-8") as f:
                m = re.search(r'^name\s*=\s*"([^"]+)"', f.read(), re.M)
            name = m.group(1) if m else pkg
        except OSError:
            pass
        if os.path.isdir(here) and not os.path.exists(os.path.join(d, "deps", name)):
            os.symlink(here, os.path.join(d, "deps", name))
    return d


def main(argv):
    jobs = min(4, os.cpu_count() or 1)
    verbose = timings = False
    files = []
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("-j", "--jobs"):
            jobs = int(argv[k + 1]); k += 2; continue
        if a in ("-v", "--verbose"):
            verbose = True
        elif a == "--timings":
            timings = True
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
    # The examples belong to a package of their own, so `( pkg_version )`
    # (spec §6.5) has a manifest to read.
    with open(os.path.join(tmpdir, "nurl.toml"), "w") as f:
        f.write('[package]\nname = "doctest"\nversion = "0.0.0"\n')
    cwd = make_cwd()
    failures, spent, skipped = [], [], []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            # A block that imports a package pulls in a whole stack (TLS,
            # HTTP, …) and takes seconds where a snippet takes milliseconds:
            # start those first so they do not trail the run.
            heavy = lambda b: any("deps/" in l for l, _ in (b.file_prelude or [])) or \
                any("deps/" in l for l in b.lines + b.prelude)
            order = sorted(run, key=lambda b: not heavy(b))
            futs = {ex.submit(check, b, nurlc, tmpdir, cwd): b for b in order}
            for fut in concurrent.futures.as_completed(futs):
                b = futs[fut]
                rc, diags, mapped, pairs, secs = fut.result()
                spent.append((secs, b))
                if any(NO_SENTINEL in m for _, m, _ in diags):
                    # The example uses an OPTIONAL native library (libpq,
                    # sqlite3, …) this build found no pkg-config for: an
                    # environment gap, not doc rot — check_examples.sh
                    # skips the same case.
                    skipped.append(b)
                    continue
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
    if timings:
        print("\nslowest blocks:")
        for secs, b in sorted(spent, key=lambda t: -t[0])[:10]:
            print(f"  {secs:6.2f}s  {b.where()}")
    for b in sorted(skipped, key=lambda b: (b.path, b.line)):
        print(f"{b.where()}: skipped — optional FFI library absent from this build")
    passed = len(run) - len(failures) - len(skipped)
    print(f"\ndoc examples: PASS {passed} · FAIL {len(failures)} · IGNORED {ignored}"
          f" · SKIP {len(skipped)}"
          f" · fence problems {len(problems)}  ({len(targets)} files)")
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
