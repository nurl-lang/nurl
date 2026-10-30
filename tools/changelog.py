#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CHANGELOG fragments: one file per change, folded in at release (Agora #211).

Every pull request used to append to the same `## [Unreleased]` spot in
CHANGELOG.md, so any two PRs conflicted there and the second had to rebase
and run CI again (about 40 min each). A PR now adds a fragment instead:

    changes/unreleased/<name>.md

named after its Agora task or PR (`t205-try-nc-lend.md`, `pr1353.md`). The
first line is the Keep a Changelog section, the rest is the entry exactly as
it will read in CHANGELOG.md:

    ### Fixed

    - **A try hands the caller an error it cannot copy only once it owns
      it** (Agora #205). …

Several entries, even in several sections, may share one fragment. The
release folds them into CHANGELOG.md and deletes them (RELEASING.md step 1).

    tools/changelog.py check              # CI: every fragment is well-formed
    tools/changelog.py preview            # CHANGELOG.md with the fragments
                                          # shown under [Unreleased]
    tools/changelog.py fold X.Y.Z [DATE]  # the release: a `## [X.Y.Z] — DATE`
                                          # section from the fragments, then
                                          # `git rm` them
"""
import datetime
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')
FRAG_DIR = os.path.join(ROOT, 'changes', 'unreleased')
# Keep a Changelog's sections, plus the two this changelog has always used.
SECTIONS = ['Added', 'Changed', 'Deprecated', 'Removed', 'Performance',
            'Fixed', 'Security', 'Known issues']
UNRELEASED = '## [Unreleased]'
NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\.md$')


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]


def fragments():
    """[(file name, {section: [entry text]})], or exits listing every problem."""
    out, errs = [], []
    names = sorted(os.listdir(FRAG_DIR), key=natural) if os.path.isdir(FRAG_DIR) else []
    for n in names:
        if n == 'README.md':
            continue
        if not NAME.match(n):
            errs.append(f'changes/unreleased/{n}: a fragment is a .md file named after its task or PR')
            continue
        text = open(os.path.join(FRAG_DIR, n), encoding='utf-8').read()
        secs, cur = {}, None
        for line in text.split('\n'):
            m = re.match(r'###\s+(.+?)\s*$', line)
            if m:
                cur = m.group(1)
                if cur not in SECTIONS:
                    errs.append(f'changes/unreleased/{n}: `### {cur}` is not one of: ' + ', '.join(SECTIONS))
                secs.setdefault(cur, [])
                continue
            if line.startswith('#'):
                errs.append(f'changes/unreleased/{n}: only `### <Section>` headings belong in a fragment')
                continue
            if cur is None:
                if line.strip():
                    errs.append(f'changes/unreleased/{n}: the first line must be a `### <Section>` heading')
                continue
            secs[cur].append(line)
        body = {k: '\n'.join(v).strip('\n') for k, v in secs.items()}
        if not body:
            errs.append(f'changes/unreleased/{n}: no `### <Section>` heading')
        for k, v in body.items():
            if not v.strip():
                errs.append(f'changes/unreleased/{n}: `### {k}` has no entry under it')
            elif not v.lstrip().startswith('- '):
                errs.append(f'changes/unreleased/{n}: an entry under `### {k}` is a `- ` list item')
        out.append((n, body))
    if errs:
        for e in errs:
            print('changelog.py: ' + e, file=sys.stderr)
        sys.exit(2)
    return out


def render(frags):
    """The section bodies, in SECTIONS order, fragments in name order."""
    parts = []
    for sec in SECTIONS:
        entries = [b[sec] for _, b in frags if sec in b]
        if entries:
            parts.append(f'### {sec}\n\n' + '\n\n'.join(entries))
    return '\n\n'.join(parts)


def split_changelog():
    text = open(CHANGELOG, encoding='utf-8').read()
    i = text.find(UNRELEASED)
    if i < 0:
        sys.exit(f'changelog.py: CHANGELOG.md has no `{UNRELEASED}` heading')
    j = text.find('\n## [', i + len(UNRELEASED))
    j = len(text) if j < 0 else j + 1
    return text[:i], text[i:j], text[j:]


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ''
    if cmd == 'check':
        frags = fragments()
        head, unrel, _ = split_changelog()
        stray = unrel[len(UNRELEASED):].strip()
        if stray and not stray.startswith('Unreleased changes are'):
            print('changelog.py: CHANGELOG.md has entries under [Unreleased]. Move them to '
                  'changes/unreleased/<task>.md (see tools/changelog.py).', file=sys.stderr)
            return 1
        print(f'changelog.py: {len(frags)} fragment(s) OK')
        return 0
    if cmd == 'preview':
        frags = fragments()
        head, unrel, rest = split_changelog()
        body = render(frags)
        sys.stdout.write(head + UNRELEASED + '\n\n' + (body + '\n\n' if body else '') + rest)
        return 0
    if cmd == 'fold':
        if len(argv) < 3 or not re.match(r'\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$', argv[2]):
            print('usage: tools/changelog.py fold X.Y.Z [YYYY-MM-DD]', file=sys.stderr)
            return 2
        version = argv[2]
        date = argv[3] if len(argv) > 3 else datetime.date.today().isoformat()
        frags = fragments()
        if not frags:
            print('changelog.py: no fragments in changes/unreleased/: nothing to release', file=sys.stderr)
            return 1
        head, unrel, rest = split_changelog()
        text = (head + UNRELEASED + '\n\n' + UNRELEASED_NOTE + '\n\n'
                + f'## [{version}] — {date}\n\n' + render(frags) + '\n\n' + rest)
        paths = [os.path.join(FRAG_DIR, n) for n, _ in frags]
        # Tracked or not, staged or not: the fragments leave the tree and
        # the index together, before CHANGELOG.md is rewritten.
        subprocess.run(['git', 'rm', '-qf', '--ignore-unmatch', '--'] + paths, cwd=ROOT, check=True)
        for p in paths:
            if os.path.exists(p):
                os.remove(p)
        with open(CHANGELOG, 'w', encoding='utf-8') as fh:
            fh.write(text)
        print(f'changelog.py: folded {len(frags)} fragment(s) into [{version}] — {date}')
        return 0
    print(__doc__, file=sys.stderr)
    return 2


UNRELEASED_NOTE = ('Unreleased changes are fragments in [`changes/unreleased/`](changes/unreleased/) '
                   'until a release folds them in here (`tools/changelog.py`).')

if __name__ == '__main__':
    sys.exit(main(sys.argv))
