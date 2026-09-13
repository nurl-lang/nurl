#!/usr/bin/env python3
"""One compiler invocation must see one version of every source file.

A FIFO supplies the first version. Its pathname is atomically replaced before
EOF is delivered, making subsequent filesystem reads see the second version
without sleeps, polling, or changes to the compiler under test.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(hasattr(os, 'mkfifo'), 'source replacement fixture needs POSIX FIFOs')
class SourceSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-source-snapshot-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        self.env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
                    'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                    'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}

    def compile_changing(self, target, old, new, entry, *flags):
        os.mkfifo(target)
        replacement = target.with_suffix('.replacement')
        replacement.write_text(new)
        failures = []

        def supply():
            try:
                with target.open('wb', buffering=0) as stream:
                    stream.write(old.encode())
                    os.replace(replacement, target)
                    # Only now close the FIFO: the compiler cannot finish its
                    # first read until the replacement is already visible.
            except BaseException as error:
                failures.append(error)

        writer = threading.Thread(target=supply, daemon=True)
        writer.start()
        run = subprocess.run([str(self.compiler), *flags, str(entry)], cwd=ROOT,
                             capture_output=True, env=self.env, timeout=30)
        writer.join(timeout=5)
        self.assertFalse(writer.is_alive(), 'compiler never opened the source')
        self.assertFalse(failures, failures)
        self.assertEqual(target.read_text(), new)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run

    def test_import_scan_and_emission_share_the_first_version(self):
        imported = self.directory / 'module.nu'
        entry = self.directory / 'main.nu'
        entry.write_text('$ `module.nu`\n@ main → i { ^ ( answer ) }\n')
        old = '@ answer → i { ^ 7 }\n'
        new = '@ answer → i { ^ 9 }\n'
        run = self.compile_changing(imported, old, new, entry)
        self.assertEqual(run.returncode, 0, run.stderr.decode())
        body = run.stdout.split(b'define i64 @__nurl_fn.answer()', 1)[1].split(b'\n}', 1)[0]
        self.assertIn(b'ret i64 7', body)
        self.assertNotIn(b'ret i64 9', body)
        # A later invocation sees the new version; this is not a stale global
        # cache shared across independent compiles.
        later = subprocess.run([str(self.compiler), str(entry)], cwd=ROOT,
                               capture_output=True, env=self.env, timeout=30)
        self.assertEqual(later.returncode, 0, later.stderr.decode())
        body = later.stdout.split(b'define i64 @__nurl_fn.answer()', 1)[1].split(b'\n}', 1)[0]
        self.assertIn(b'ret i64 9', body)

    def test_deferred_root_diagnostic_uses_the_first_version(self):
        entry = self.directory / 'main.nu'
        old = '''$ `stdlib/core/vec.nu`
@ consume sink ( Vec i ) values → v { ( vec_free [i] values ) }
@ main → i {
    : ( Vec i ) owned ( vec_new [i] )
    ( consume owned )
    ( nurl_println_int ( vec_len [i] owned ) )
    ^ 0
}
'''
        new = '@ main → i { ^ 0 }\n'
        run = self.compile_changing(entry, old, new, entry, '--check')
        self.assertEqual(run.returncode, 1, run.stderr.decode())
        self.assertEqual(run.stdout, b'')
        self.assertIn(b'( nurl_println_int ( vec_len [i] owned ) )', run.stderr)
        self.assertNotIn(b'@ main', run.stderr)

    def test_coverage_outputs_share_one_frontend_snapshot(self):
        imported = self.directory / 'module.nu'
        entry = self.directory / 'main.nu'
        entry.write_text('$ `module.nu`\n@ main → i { ^ ( answer ) }\n')
        staged = self.directory / 'stage.ll'
        final = self.directory / 'program'
        notes = self.directory / 'stage.gcno'
        run = self.compile_changing(imported, '@ answer → i { ^ 7 }\n',
                                    '@ answer → i { ^ 9 }\n', entry,
                                    f'--coverage={final}', f'--coverage-notes={notes}',
                                    f'--coverage-link-ir={staged}')
        self.assertEqual(run.returncode, 0, run.stderr.decode())
        alternate = staged.read_bytes()
        for module in (run.stdout, alternate):
            body = module.split(b'define i64 @__nurl_fn.answer()', 1)[1].split(b'\n}', 1)[0]
            self.assertIn(b'ret i64 7', body)
            self.assertNotIn(b'ret i64 9', body)
        self.assertIn(str(final.with_suffix('.gcno')).encode(), run.stdout)
        self.assertNotIn(str(notes).encode(), run.stdout)
        self.assertIn(str(notes).encode(), alternate)
        # The last line is the structured notes mapping. Every instruction,
        # type and debug location preceding it is emitted only once.
        self.assertEqual(run.stdout.rsplit(b'\n', 2)[0], alternate.rsplit(b'\n', 2)[0])


if __name__ == '__main__':
    unittest.main(verbosity=2)
