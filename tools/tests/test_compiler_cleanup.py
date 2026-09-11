#!/usr/bin/env python3
"""Rejected compilation must preserve diagnostics, emit no IR and release owners."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class CompilerCleanupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nurl-compiler-errors-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.compiler = Path(os.environ.get('NURLC', ROOT/'build/nurlc')).resolve()
        self.env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
                    'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                    'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}

    def reject(self, path, *flags, data=None, diagnostic=b'error:'):
        run = subprocess.run([str(self.compiler), *flags, str(path)],
            cwd=ROOT, input=data, capture_output=True, env=self.env, timeout=60)
        self.assertEqual(run.returncode, 1, run.stderr.decode(errors='replace'))
        self.assertEqual(run.stdout, b'', run.stdout[:500])
        self.assertIn(diagnostic, run.stderr)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        self.assertNotIn(b'internal compiler error:', run.stderr)

    def test_body_errors_across_output_modes(self):
        path = self.root/'input.nu'
        path.write_text('@ broken → i { ^ missing_a }\n@ main → i { ^ missing_b }\n')
        for flags in [(), ('--check',), ('--g',), ('--lint',),
                      ('--split=2', '--split-min=1', f'--split-out={self.root}/part')]:
            with self.subTest(flags=flags):
                self.reject(path, *flags, diagnostic=b'2 previous errors')
        self.assertEqual(list(self.root.glob('part.*')), [])

    def test_stdin_errors_use_live_source_and_release_it(self):
        path = self.root/'input.nu'
        path.write_text('@ main → i { ^ 0 }\n')
        self.reject(path, '--stdin', '--check',
                    data='@ main → i { ^ unsaved_name }\n'.encode(),
                    diagnostic=b'unsaved_name')

    def test_lint_import_walk_releases_mutable_cursors(self):
        run = subprocess.run([str(self.compiler), '--lint', '--check',
                              str(ROOT/'compiler/tests/argv_test.nu')],
            cwd=ROOT, capture_output=True, env=self.env, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertEqual(run.stdout, b'')
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)

    def test_prepasses_deferred_checks_and_import_recovery(self):
        cases = ['diag_import_missing', 'diag_generic_fn_unclosed',
                 'diag_generic_struct_unclosed', 'diag_trait_order_assoc_missing',
                 'diag_generic_body_error_loc', 'diag_match_arm_recover',
                 'borrow_sink_enum_after', 'diag_bad_type_token',
                 'diag_closure_arity_few', 'diag_send_chan_send',
                 'should_fail_unterminated_trait', 'diag_removed_print_bool']
        for case in cases:
            with self.subTest(case=case):
                self.reject(ROOT/f'compiler/tests/{case}.nu', '--check')

    def test_all_corpus_rejections_release_the_compilation(self):
        # Derive the sweep from current golden verdicts instead of preserving
        # a historical count. Use the real runners' per-fixture compiler flags.
        cases = sorted(path.stem for path in (ROOT/'compiler/tests/outputs').glob('*.txt')
                       if path.read_bytes().startswith(b'COMPILE FAIL\n'))
        self.assertTrue(cases, 'no rejected-source fixtures found')
        for case in cases:
            with self.subTest(case=case):
                flag = subprocess.run(['bash', '-c',
                    'source compiler/tests/test_harness.sh; test_compiler_flag "$1"',
                    'compiler-cleanup', case], cwd=ROOT, capture_output=True,
                    text=True, timeout=10, check=True).stdout.strip()
                self.reject(ROOT/f'compiler/tests/{case}.nu', '--check',
                            *([flag] if flag else []))

    def test_error_limit_still_cleans_the_compilation(self):
        path = self.root/'many.nu'
        path.write_text(''.join(f'@ broken_{i} → i {{ ^ missing_{i} }}\n' for i in range(30)))
        self.reject(path, '--check', diagnostic=b'too many errors (20)')

    def test_invalid_cli_returns_without_leaking_arguments(self):
        path = self.root/'input.nu'
        path.write_text('@ main → i { ^ 0 }\n')
        for flags in [('--check', 'second.nu'), ('--split=2',), ('--g', '--split=2', '--split-out=x')]:
            with self.subTest(flags=flags):
                self.reject(path, *flags, diagnostic=b'nurlc')

if __name__ == '__main__':
    unittest.main(verbosity=2)
