#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/sweep_classify.py — say WHAT changed in the files a tree sweep
#  reports as different.
#
#  tools/tree_sweep.sh answers "the same or not" by hashing each file's
#  IR. Reading a hundred differing files by hand is where a hunt loses
#  its afternoon, and most differences are noise: register numbering and
#  a dead instruction no longer emitted. This recompiles each differing
#  file with both compilers, splits the IR into functions, renumbers the
#  registers, drops pure instructions whose result nothing reads, and
#  lists the functions that still differ — grouped, so one changed
#  stdlib helper shows once with its count instead of once per file.
#
#  Usage:
#    tools/sweep_classify.py SWEEP_OUT BASE_BIN NEW_BIN
#    tools/sweep_classify.py SWEEP_OUT BASE_BIN NEW_BIN --fn FILE FUNC
#
#  Run it from the checkout that was swept. SWEEP_OUT is tree_sweep's
#  NURL_SWEEP_OUT directory (base/, new/ and pkgroot/ are read from it);
#  the IR is written to SWEEP_OUT/ir/. The
#  second form prints one function's normalised diff — a plain line
#  diff, one hunk per run of changed lines.
# ============================================================
import collections
import difflib
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# The repository the sweep ran in: the one the caller stands in, which is
# not always the one this script was read from.
ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip() \
    or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REG = re.compile(r'%r\d+')
PURE = re.compile(r'^\s*(%r\d+) = (xor|and|or|load|icmp|extractvalue|insertvalue|phi|zext|sext|trunc|select|bitcast|getelementptr|ptrtoint)\b')
DEFINE = re.compile(r'^define [^@]*@("[^"]+"|[^(\s]+)\(')


def tracked_sources():
    out = subprocess.run(['git', 'ls-files', '*.nu'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return {f.replace('/', '__'): f for f in out.split()}


def differing(sweep_out):
    by_flat = tracked_sources()
    files = []
    base_dir = os.path.join(sweep_out, 'base')
    for name in sorted(os.listdir(base_dir)):
        if not name.endswith('.txt'):
            continue
        b = os.path.join(base_dir, name)
        n = os.path.join(sweep_out, 'new', name)
        if not os.path.exists(n) or open(b, 'rb').read() != open(n, 'rb').read():
            files.append(by_flat.get(name[:-4], name[:-4].replace('__', '/')))
    return files


def compile_ir(sweep_out, binary, path, dest):
    # The same invocation tree_sweep makes: a package file from its
    # installed-layout root, anything else from the repository root.
    parts = path.split('/')
    pkgroot = os.path.join(sweep_out, 'pkgroot')
    if len(parts) > 3 and parts[0] == 'packages' and os.path.isdir(os.path.join(pkgroot, parts[1])):
        cwd, rel = os.path.join(pkgroot, parts[1]), '/'.join(parts[2:])
        env = dict(os.environ, NURL_STDLIB=ROOT)
    else:
        cwd, rel, env = ROOT, path, None
    r = subprocess.run([binary, rel], cwd=cwd, env=env, capture_output=True, text=True)
    with open(dest, 'w') as f:
        f.write(r.stdout)
    return r.returncode, r.stderr


def functions(text):
    fns, cur, body = {}, None, []
    for line in text.split('\n'):
        m = DEFINE.match(line)
        if m:
            cur, body = m.group(1), []
        elif cur is not None:
            if line.startswith('}'):
                fns[cur] = body
                cur = None
            elif not line.lstrip().startswith(';'):
                body.append(line)
    return fns


def drop_dead(lines):
    # A pure instruction whose register is named once (its own definition)
    # is dead; dropping one can make another dead, so repeat.
    while True:
        uses = collections.Counter()
        for line in lines:
            uses.update(REG.findall(line))
        dead = {i for i, line in enumerate(lines)
                if (m := PURE.match(line)) and uses[m.group(1)] == 1}
        if not dead:
            return lines
        lines = [line for i, line in enumerate(lines) if i not in dead]


def normalise(lines):
    names = {}
    out = []
    for line in drop_dead(lines):
        out.append(REG.sub(lambda m: names.setdefault(m.group(0), '%v' + str(len(names))), line))
    return out


def same(a, b):
    return a == b or normalise(a) == normalise(b)


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        sys.exit('usage: tools/sweep_classify.py SWEEP_OUT BASE_BIN NEW_BIN [--fn FILE FUNC]')
    sweep_out, base_bin, new_bin = args[:3]
    ir = {w: os.path.join(sweep_out, 'ir', w) for w in ('base', 'new')}
    for d in ir.values():
        os.makedirs(d, exist_ok=True)

    if len(args) == 6 and args[3] == '--fn':
        path, fn = args[4], args[5]
        flat = path.replace('/', '__') + '.ll'
        for w, binary in (('base', base_bin), ('new', new_bin)):
            if not os.path.exists(os.path.join(ir[w], flat)):
                compile_ir(sweep_out, binary, path, os.path.join(ir[w], flat))
        a = normalise(functions(open(os.path.join(ir['base'], flat)).read()).get(fn, []))
        b = normalise(functions(open(os.path.join(ir['new'], flat)).read()).get(fn, []))
        sys.stdout.writelines(l + '\n' for l in difflib.unified_diff(a, b, 'base', 'new', lineterm='', n=3))
        return

    files = differing(sweep_out)
    diag = []

    def one(path):
        flat = path.replace('/', '__') + '.ll'
        rb, eb = compile_ir(sweep_out, base_bin, path, os.path.join(ir['base'], flat))
        rn, en = compile_ir(sweep_out, new_bin, path, os.path.join(ir['new'], flat))
        if rb != rn or eb != en:
            return path, None
        fa = functions(open(os.path.join(ir['base'], flat)).read())
        fb = functions(open(os.path.join(ir['new'], flat)).read())
        changed = []
        for k in sorted(set(fa) | set(fb)):
            if k not in fa or k not in fb:
                changed.append(('+' if k in fb else '-') + k)
            elif not same(fa[k], fb[k]):
                changed.append(k)
        return path, changed

    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        results = list(pool.map(one, files))

    by_fn = collections.Counter()
    example = {}
    noise = 0
    for path, changed in results:
        if changed is None:
            diag.append(path)
        elif not changed:
            noise += 1
        for k in changed or []:
            # An instance's suffix (`__fp12`) varies per file, and a split
            # build names a function without `__nurl_fn.`: group by the
            # source name.
            key = re.sub(r'__fp\d+$', '', re.sub(r'^([+-]?)__nurl_fn\.', r'\1', k))
            by_fn[key] += 1
            example.setdefault(key, path)
    print(f'{len(files)} file(s) differ; {noise} only in register numbering or dead instructions; '
          f'{len(diag)} in exit code or diagnostics.')
    for path in diag:
        print(f'  diagnostics: {path}')
    for k, c in by_fn.most_common():
        print(f'  {c:4} {k}   e.g. {example[k]}')


if __name__ == '__main__':
    main()
