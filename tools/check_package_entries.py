#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Every package's entry points compile, the way a consumer compiles them.

Nothing compiled packages/ on a PR. The compiler tightened under them —
a soundness rule (a frozen Arc payload handed to a writer, a view beside
the container a closure changes) rejects what it used to accept — and
lingbot-map, map-anything, onnx and benchmark stopped compiling with
nothing red: found only by building them by hand.

An entry point is `src/main.nu` (a program) and `src/<name>.nu` (the
library a consumer imports; `-` in the name spelled `_`). Each is run
through `nurlc --check --no-dce` — the whole frontend, borrow checker
included, no IR written, and every function body, not only those `main`
reaches (a library's entry wrapped in an empty `main` reaches none) —
from a scratch root laid out as an installed consumer's:
`deps/<name>` links every in-tree package under the name its manifest
gives it, so the entry is imported as `$ \\`deps/<pkg>/src/<entry>\\`` and
each `deps/…` and sibling import resolves as it does after
`nurlpkg install`. A program's entry (it defines `main`) is checked
as it is; a library's is wrapped with an empty `main`.

An entry whose stdlib module needs an optional native library the
toolchain was built without ("… is required but no build-time
sentinel") is SKIPPED, not failed: that is the host, not the package.

Usage:  tools/check_package_entries.py [-j N] [-v] [PKG…]
        NURL_PKGCHECK_JOBS=N (default min(4, cores))
Exit:   0 all compile (or skip) · 1 a failure · 2 no build/nurlc
"""
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NO_SENTINEL = "is required but no build-time sentinel"
MAIN = re.compile(r"^(?:pub\s+)?(?:unsafe\s+)?@\s+main\b", re.M)


def manifest_name(pkg_dir):
    try:
        with open(os.path.join(pkg_dir, "nurl.toml"), encoding="utf-8") as f:
            m = re.search(r'^name\s*=\s*"([^"]+)"', f.read(), re.M)
    except OSError:
        return None
    return m.group(1) if m else None


def packages(root):
    """[(dir name, manifest name)] of every directory with a manifest."""
    base = os.path.join(root, "packages")
    out = []
    for d in sorted(os.listdir(base)):
        name = manifest_name(os.path.join(base, d))
        if name:
            out.append((d, name))
    return out


def entries(root, pkg_dir):
    """The package's entry files under src/, in check order."""
    src = os.path.join(root, "packages", pkg_dir, "src")
    name = manifest_name(os.path.join(root, "packages", pkg_dir)) or pkg_dir
    found = []
    for f in ("main.nu", name.replace("-", "_") + ".nu", name + ".nu"):
        if f not in found and os.path.isfile(os.path.join(src, f)):
            found.append(f)
    return found


def make_root(root, pkgs):
    d = tempfile.mkdtemp(prefix="nurl-pkgcheck-")
    os.symlink(os.path.join(root, "stdlib"), os.path.join(d, "stdlib"))
    os.mkdir(os.path.join(d, "deps"))
    for pkg_dir, name in pkgs:
        link = os.path.join(d, "deps", name)
        if not os.path.lexists(link):
            os.symlink(os.path.join(root, "packages", pkg_dir), link)
    return d


def wrapper(name, entry, is_program):
    text = f"$ `deps/{name}/src/{entry}`\n"
    return text if is_program else text + "\n@ main → i { ^ 0 }\n"


def classify(rc, stderr):
    """'ok', 'skip' or 'fail' for one compile."""
    if rc == 0:
        return "ok"
    if NO_SENTINEL in stderr:
        return "skip"
    return "fail"


def check_one(nurlc, cwd, root, pkg_dir, name, entry):
    path = os.path.join(root, "packages", pkg_dir, "src", entry)
    with open(path, encoding="utf-8", errors="replace") as f:
        is_program = bool(MAIN.search(f.read()))
    unit = os.path.join(cwd, re.sub(r"[^\w]", "_", f"{name}_{entry}"))
    with open(unit, "w", encoding="utf-8") as f:
        f.write(wrapper(name, entry, is_program))
    t0 = time.monotonic()
    env = dict(os.environ, NURL_STDLIB=root)
    try:
        p = subprocess.run([nurlc, "--check", "--no-dce", unit], cwd=cwd, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                           text=True, errors="replace", timeout=600)
        rc, err = p.returncode, p.stderr
    except subprocess.TimeoutExpired:
        rc, err = 124, "nurlc --check timed out after 600 s"
    return pkg_dir, entry, classify(rc, err), err, time.monotonic() - t0


def main(argv):
    jobs = int(os.environ.get("NURL_PKGCHECK_JOBS", min(4, os.cpu_count() or 1)))
    verbose = False
    only = []
    k = 0
    while k < len(argv):
        a = argv[k]
        if a in ("-j", "--jobs"):
            jobs = int(argv[k + 1])
            k += 2
            continue
        if a in ("-v", "--verbose"):
            verbose = True
        else:
            only.append(a.rstrip("/").split("/")[-1])
        k += 1
    nurlc = os.path.join(ROOT, "build", "nurlc")
    if not os.access(nurlc, os.X_OK):
        print("error: build/nurlc not built — run ./build.sh first", file=sys.stderr)
        return 2
    pkgs = packages(ROOT)
    unknown = [o for o in only if o not in {d for d, _ in pkgs}]
    if unknown:
        print(f"error: no such package: {', '.join(unknown)}", file=sys.stderr)
        return 2
    cwd = make_root(ROOT, pkgs)
    work = [(d, n, e) for d, n in pkgs if not only or d in only for e in entries(ROOT, d)]
    results = []
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            futs = [ex.submit(check_one, nurlc, cwd, ROOT, d, n, e) for d, n, e in work]
            for fu in concurrent.futures.as_completed(futs):
                results.append(fu.result())
    finally:
        shutil.rmtree(cwd, ignore_errors=True)
    results.sort()
    fails = [r for r in results if r[2] == "fail"]
    skips = [r for r in results if r[2] == "skip"]
    for pkg_dir, entry, verdict, err, secs in results:
        if verdict == "fail":
            print(f"packages/{pkg_dir}/src/{entry}: FAIL")
            lines = [l for l in err.splitlines() if l.strip()]
            for l in (lines if verbose else lines[:6]):
                print("    " + l)
        elif verdict == "skip":
            print(f"packages/{pkg_dir}/src/{entry}: SKIP (an optional native library this build lacks)")
        elif verbose:
            print(f"packages/{pkg_dir}/src/{entry}: ok ({secs:.1f} s)")
    print(f"\npackage entry points: PASS {len(results) - len(fails) - len(skips)} · "
          f"FAIL {len(fails)} · SKIP {len(skips)}  ({len({r[0] for r in results})} packages, jobs={jobs})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
