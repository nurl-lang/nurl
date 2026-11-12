#!/usr/bin/env python3
"""A package's text files are LF in every checkout (Agora #705).

`nurlpkg publish` packs a package's files as the working copy holds them.
With core.autocrlf=true a Windows checkout gave every text file that
.gitattributes did not pin CRLF line ends, so a registry tarball's README,
nurl.toml, CHANGELOG and line-based test data depended on the machine
that packed it (tokenizer 0.6.0, nurldb 0.3.0).

Two checks, on any platform:
  * every file under packages/ is either text with `eol=lf` or binary —
    a new file type cannot slip back to the platform's line ends;
  * no file of the checkout is CRLF in the index or in the working tree.
    On the Windows runner (core.autocrlf=true) that is the check that a
    tarball packed there holds the bytes a Linux checkout of the commit
    does.
"""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def eol_rows():
    """(index eol, worktree eol, attributes, path) for each file under packages/."""
    out = subprocess.run(
        ['git', 'ls-files', '--eol', '--', 'packages'],
        cwd=ROOT, check=True, capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        # `i/lf    w/lf    attr/text=auto eol=lf \tpath`: the path follows a tab.
        meta, path = line.split('\t', 1)
        fields = meta.split()
        attr = meta[meta.index('attr/') + 5:].strip()
        rows.append((fields[0][2:], fields[1][2:], attr, path))
    return rows


class PackageEol(unittest.TestCase):
    def setUp(self):
        self.rows = eol_rows()
        self.assertGreater(len(self.rows), 0, 'no tracked files under packages/')

    def test_every_file_is_lf_text_or_binary(self):
        loose = [p for _, _, a, p in self.rows
                 if not ('eol=lf' in a.split() or '-text' in a.split())]
        self.assertEqual(loose, [], 'files under packages/ whose line ends follow the platform; '
                         'pin them in .gitattributes (text eol=lf, or binary)')

    def test_no_crlf_in_index_or_checkout(self):
        crlf = [f'{p} (index {i}, worktree {w})' for i, w, _, p in self.rows
                if i in ('crlf', 'mixed') or w in ('crlf', 'mixed')]
        self.assertEqual(crlf, [], 'package files with CRLF line ends: nurlpkg publish would pack them '
                         'as they are; check them out again with LF (git add --renormalize)')


if __name__ == '__main__':
    unittest.main()
