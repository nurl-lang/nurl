#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""formal/corpus/map.tsv, generated from the probes' own headers.

Every probe in tools/fuzz/holes/ (and tools/fuzz/holes/stdlib/) carries one
line in its leading comment block:

    // map: <rule> | <phase> | <nurlc> | <old id> | <note>

  rule    the MEMORY.md section or typing rule that rejects it (`§7.6`,
          `CallT.summary`, ...)
  phase   the proof phase that covers it: A1, A2, A3 or B
  nurlc   what the compiler does with it today: `rejected`, or
          `runs-clean` (it compiles and runs clean under ASan/LSan)
  old id  the hNNN number the probe had before Agora #212, or `-` for a
          probe added after it. Old CHANGELOG entries, commits and Agora
          posts name probes by that number; `grep h941 map.tsv` finds them.
          (h918–h923 each name two probes: two PRs claimed the same range.)
  note    one line: what broke

map.tsv is that table, sorted by probe name. It is generated where it is
read and never committed (Agora #307): build.sh, tools/install-toolchain.sh
and the nurlapi image write it with tools/fuzz/holes/map.sh (POSIX sh +
awk, since build.sh needs no Python), and webdocs reads the `// map:` lines
itself. A pull request that adds a probe adds its `// map:` line and nothing
else, so two such PRs never conflict. CI's shared-files job runs `--lint`
and requires this script and map.sh to print the same table.

    tools/fuzz/holes/map.py            # print the table
    tools/fuzz/holes/map.py --lint     # CI: every probe's `// map:` line is well formed
    tools/fuzz/holes/map.py --write    # write formal/corpus/map.tsv here (git-ignored)
    tools/fuzz/holes/map.py --counts   # totals per phase and verdict
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
HOLES = os.path.join(ROOT, 'tools', 'fuzz', 'holes')
MAP = os.path.join(ROOT, 'formal', 'corpus', 'map.tsv')
HEADER = ['probe', 'rule', 'phase', 'note', 'nurlc', 'old_id']
PHASES = ('A1', 'A2', 'A3', 'B')
VERDICTS = ('rejected', 'runs-clean')
NAME = re.compile(r'[a-z0-9]+(?:_[a-z0-9]+)*$')


def probe_files():
    for sub in ('', 'stdlib'):
        d = os.path.join(HOLES, sub)
        for n in sorted(os.listdir(d)):
            if n.endswith('.nu'):
                yield (sub + '/' if sub else '') + n[:-3]


def rows():
    out, errs = [], []
    for probe in probe_files():
        path = os.path.join(HOLES, probe + '.nu')
        base = probe.rsplit('/', 1)[-1]
        if not NAME.match(base):
            errs.append(f'{probe}.nu: a probe is named in lower_snake_case, with no hNNN prefix')
        maps = []
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                if not line.startswith('//'):
                    break
                if line.startswith('// map:'):
                    maps.append(line[len('// map:'):].strip())
        if len(maps) != 1:
            errs.append(f'{probe}.nu: needs exactly one `// map: rule | phase | nurlc | old id | note` '
                        f'line in its leading comment block (found {len(maps)})')
            continue
        f = [x.strip() for x in maps[0].split('|', 4)]
        if len(f) != 5 or not all(f):
            errs.append(f'{probe}.nu: `// map:` needs five fields: rule | phase | nurlc | old id | note')
            continue
        rule, phase, verdict, old, note = f
        if phase not in PHASES:
            errs.append(f'{probe}.nu: phase {phase!r} is not one of {", ".join(PHASES)}')
        if verdict not in VERDICTS:
            errs.append(f'{probe}.nu: nurlc {verdict!r} is not one of {", ".join(VERDICTS)}')
        # Not unique: h918–h923 were each claimed twice in the hNNN era.
        if old != '-' and not re.match(r'h\d+$', old):
            errs.append(f'{probe}.nu: old id {old!r} is neither hNNN nor -')
        out.append([probe, rule, phase, note, verdict, old])
    return out, errs


def table(rs):
    return '\n'.join('\t'.join(r) for r in [HEADER] + rs) + '\n'


def main(argv):
    rs, errs = rows()
    if errs:
        for e in errs:
            print('map.py: ' + e, file=sys.stderr)
        return 2
    text = table(rs)
    mode = argv[1] if len(argv) > 1 else ''
    if mode == '--write':
        with open(MAP, 'w', encoding='utf-8') as fh:
            fh.write(text)
        print(f'map.py: wrote {len(rs)} probes to formal/corpus/map.tsv')
    elif mode in ('--lint', '--check'):
        # (`--check` is the old name: the table it compared against is no
        # longer committed, so the lint is all there is to check.)
        print(f'map.py: the {len(rs)} probes each have a well-formed `// map:` line')
    elif mode == '--counts':
        print(f'probes: {len(rs)}')
        for p in PHASES:
            print(f'  {p}: {sum(1 for r in rs if r[2] == p)}')
        for v in VERDICTS:
            print(f'  {v}: {sum(1 for r in rs if r[4] == v)}')
    elif mode == '':
        sys.stdout.write(text)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
