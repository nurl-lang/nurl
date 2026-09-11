#!/usr/bin/env python3
"""Exercise the real pre-commit hook against isolated Git indexes and formatters."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = Path(os.environ.get('NURL_PRECOMMIT_HOOK', ROOT / '.githooks/pre-commit')).resolve()
RAW = '@ main → i {^0}\n'
CANONICAL = '@ main → i { ^ 0 }\n'


@unittest.skipUnless(shutil.which('git') and shutil.which('bash'), 'Git and Bash required')
class PreCommitTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nurl-hook-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.git('init', '-q')
        self.source = self.root / 'source.nu'
        self.source.write_text(RAW)
        self.git('add', 'source.nu')
        (self.root / 'build').mkdir()
        self.formatter = self.root / 'build/nurlfmt'

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=True).stdout

    def run_hook(self, body):
        self.formatter.write_text('#!/usr/bin/env bash\nset -eu\n' + body + '\n')
        self.formatter.chmod(0o755)
        return subprocess.run(['bash', str(HOOK)], cwd=self.root, env=self.env,
                              capture_output=True, text=True, timeout=15)

    def test_formatter_failure_blocks_fully_staged_source(self):
        run = self.run_hook("echo 'formatter refused fixture' >&2; exit 2")
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('formatter refused fixture', run.stderr)
        self.assertEqual(self.git('show', ':source.nu'), RAW)

    def test_partial_formatter_output_is_not_staged_on_failure(self):
        run = self.run_hook('printf "broken\\n" > "$2"; exit 2')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(self.source.read_text(), 'broken\n')
        self.assertEqual(self.git('show', ':source.nu'), RAW)

    def test_successful_format_is_staged(self):
        run = self.run_hook('printf "@ main → i { ^ 0 }\\n" > "$2"')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(self.source.read_text(), CANONICAL)
        self.assertEqual(self.git('show', ':source.nu'), CANONICAL)

    def test_partially_staged_source_is_checked_without_rewriting(self):
        self.source.write_text(RAW + '// unstaged\n')
        run = self.run_hook('test "$1" = --check; exit 1')
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(self.source.read_text(), RAW + '// unstaged\n')
        self.assertEqual(self.git('show', ':source.nu'), RAW)


if __name__ == '__main__':
    unittest.main(verbosity=2)
