#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""tools/tree_sweep.sh against stand-in compilers in an isolated repository.

A compile that hangs is stopped at NURL_SWEEP_TIMEOUT and recorded as
`exit=timeout`, named first in the summary (agora #794); a compile far
slower with the new compiler is reported; identical transcripts still pass.
No toolchain: the compilers are shell scripts.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

# A stand-in compiler: prints a fixed IR, and sleeps on the files its
# SLEEP_ON names (by basename, comma-separated) for SLEEP_FOR seconds.
COMPILER = r'''#!/usr/bin/env bash
f="$(basename "$1")"
IFS=, read -ra slow <<<"${SLEEP_ON:-}"
for s in "${slow[@]}"; do
    [[ "$s" == "$f" ]] && sleep "${SLEEP_FOR:-30}"
done
echo "; ir of $f"
exit 0
'''


class TreeSweepTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-sweep-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'repo'
        (self.root / 'tools').mkdir(parents=True)
        shutil.copy2(ROOT / 'tools/tree_sweep.sh', self.root / 'tools/tree_sweep.sh')
        for name in ('a.nu', 'b.nu', 'c.nu'):
            (self.root / name).write_text('@ main → i { ^ 0 }\n')
        git = ['git', '-C', str(self.root), '-c', 'user.name=t', '-c', 'user.email=t@t']
        subprocess.run(git[:3] + ['init', '-q'], check=True)
        subprocess.run(git + ['add', '-A'], check=True)
        subprocess.run(git + ['commit', '-q', '-m', 'fixture'], check=True)
        self.bins = {}
        for side in ('base', 'new'):
            p = Path(self.tmp.name) / f'nurlc_{side}'
            p.write_text(COMPILER)
            p.chmod(0o755)
            self.bins[side] = p

    def sweep(self, base_env=None, new_env=None, **env):
        # Each side's compiler reads its own SLEEP_ON through a wrapper, so
        # the two can differ.
        wrapped = {}
        for side, extra in (('base', base_env or {}), ('new', new_env or {})):
            w = Path(self.tmp.name) / f'wrap_{side}'
            exports = ''.join(f'export {k}={v!r}\n' for k, v in extra.items())
            w.write_text(f'#!/usr/bin/env bash\n{exports}exec {self.bins[side]} "$@"\n')
            w.chmod(0o755)
            wrapped[side] = w
        e = dict(os.environ, NURL_SWEEP_JOBS='3', **env)
        e.pop('NURL_SWEEP_OUT', None)
        t0 = time.monotonic()
        r = subprocess.run(
            ['bash', str(self.root / 'tools/tree_sweep.sh'),
             '--base-bin', str(wrapped['base']), '--new-bin', str(wrapped['new'])],
            cwd=self.root, env=e, capture_output=True, text=True, timeout=120)
        return r, time.monotonic() - t0

    def test_identical_passes(self):
        r, _ = self.sweep()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('3 file(s) byte-identical', r.stdout)

    def test_new_side_hang_is_stopped_and_named_first(self):
        r, took = self.sweep(new_env={'SLEEP_ON': 'b.nu', 'SLEEP_FOR': '60'},
                             NURL_SWEEP_TIMEOUT='2')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertLess(took, 30, 'the hang was not stopped at the limit')
        self.assertIn('TIMEOUT (2s, new): b.nu', r.stdout)
        self.assertIn('DIFFERS: b.nu', r.stdout)
        self.assertLess(r.stdout.index('TIMEOUT'), r.stdout.index('DIFFERS'))
        self.assertIn('1 file(s) TIMED OUT after 2s', r.stdout)

    def test_both_sides_hanging_still_fail(self):
        slow = {'SLEEP_ON': 'c.nu', 'SLEEP_FOR': '60'}
        r, _ = self.sweep(base_env=slow, new_env=slow, NURL_SWEEP_TIMEOUT='2')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn('TIMEOUT (2s, base and new): c.nu', r.stdout)
        self.assertNotIn('DIFFERS', r.stdout)

    def test_far_slower_compile_is_reported(self):
        r, _ = self.sweep(new_env={'SLEEP_ON': 'a.nu', 'SLEEP_FOR': '1.5'},
                          NURL_SWEEP_TIMEOUT='20')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('SLOWER (', r.stdout)
        self.assertIn('): a.nu', r.stdout)
        self.assertIn('1 file(s) compile more than 5x slower', r.stdout)


if __name__ == '__main__':
    unittest.main()
