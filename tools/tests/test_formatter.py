#!/usr/bin/env python3
"""Real formatter CLI and reusable formatter ownership controls.

Build first, then run normally or with NURL_SAN=1 and NURLFMT pointing to
an instrumented formatter. Sanitizer failures must fail even expected-error cases.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RAW = '@ main → i {^0}'.encode()
CANONICAL = '@ main → i { ^ 0 }\n'.encode()


class FormatterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.formatter = Path(os.environ.get('NURLFMT', ROOT / 'build/nurlfmt')).resolve()
        if not cls.formatter.is_file():
            raise RuntimeError(f'Build {cls.formatter} before running this suite')
        if os.environ.get('NURL_SAN') == '1':
            definitions = [line for line in cls.formatter.with_suffix('.ll').read_text().splitlines()
                           if line.startswith('define ')]
            if not definitions or not all('sanitize_address' in line for line in definitions):
                raise AssertionError('formatter is not fully instrumented')
        cls.env = {**os.environ, 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                   'UBSAN_OPTIONS': 'halt_on_error=1', 'DEBUGINFOD_URLS': ''}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-formatter-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.path = self.root / 'source ä.nu'
        self.path.write_bytes(RAW)

    def run_fmt(self, *args, data=b'', **kwargs):
        run = subprocess.run([str(self.formatter), *map(str, args)], input=data,
                             cwd=self.root, capture_output=True, env=self.env,
                             timeout=20, **kwargs)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run

    def test_stdin_formats_and_checks_without_source_output(self):
        for args in [(), ('--stdin',)]:
            with self.subTest(args=args):
                run = self.run_fmt(*args, data=RAW)
                self.assertEqual((run.returncode, run.stdout, run.stderr), (0, CANONICAL, b''))
                for data, code in [(RAW, 1), (CANONICAL, 0), (b'', 0)]:
                    check = self.run_fmt('--check', *args, data=data)
                    self.assertEqual((check.returncode, check.stdout), (code, b''), check.stderr)

    def test_file_modes_and_unchanged_write(self):
        run = self.run_fmt(self.path)
        self.assertEqual((run.returncode, run.stdout), (0, CANONICAL), run.stderr)
        self.assertEqual(self.path.read_bytes(), RAW)
        self.assertEqual(self.run_fmt('--check', self.path).returncode, 1)
        run = self.run_fmt('--write', self.path)
        self.assertEqual((run.returncode, run.stdout, run.stderr), (0, b'', b''))
        self.assertEqual(self.path.read_bytes(), CANONICAL)
        os.utime(self.path, ns=(1000000000, 1000000000))
        self.assertEqual(self.run_fmt('--write', self.path).returncode, 0)
        self.assertEqual(self.path.stat().st_mtime_ns, 1000000000)
        self.assertEqual(self.run_fmt('--check', self.path).returncode, 0)

    def test_many_files_fold_errors_and_release_paths(self):
        paths = []
        for number in range(40):
            path = self.root / f'file {number}.nu'
            path.write_bytes(CANONICAL if number % 2 else RAW)
            paths.append(path)
        self.assertEqual(self.run_fmt('--check', *paths).returncode, 1)
        missing = self.root / 'absent.nu'
        self.assertEqual(self.run_fmt('--check', missing, *paths).returncode, 2)
        self.assertEqual(self.run_fmt('--check', *paths, missing).returncode, 2)
        self.assertEqual(self.run_fmt('--write', *paths).returncode, 0)
        self.assertTrue(all(path.read_bytes() == CANONICAL for path in paths))

    def test_usage_errors_do_not_read_or_write(self):
        for args in [('--check', '--write'), ('--check', '--write', '--stdin'),
                     ('--stdin', self.path), ('--write',), ('--write', '--stdin'),
                     (self.path, '--invalid')]:
            with self.subTest(args=args):
                run = self.run_fmt(*args, data=RAW)
                self.assertEqual((run.returncode, run.stdout), (2, b''), run.stderr)
                self.assertTrue(run.stderr)
                self.assertEqual(self.path.read_bytes(), RAW)

    def test_help_version_and_end_of_options(self):
        for option in ['--help', '--version', '-v', 'version']:
            run = self.run_fmt(self.path, option)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertTrue(run.stdout or run.stderr)
            self.assertEqual(self.path.read_bytes(), RAW)
        dash = self.root / '--check'
        dash.write_bytes(RAW)
        run = self.run_fmt('--', '--check')
        self.assertEqual((run.returncode, run.stdout), (0, CANONICAL), run.stderr)

    def test_failed_file_reads_are_errors_in_every_mode(self):
        for path in [self.root, self.root / 'missing.nu']:
            for options in [(), ('--check',), ('--write',)]:
                with self.subTest(path=path, options=options):
                    run = self.run_fmt(*options, path)
                    self.assertEqual((run.returncode, run.stdout), (2, b''), run.stderr)
                    self.assertTrue(run.stderr)
        self.assertTrue(self.root.is_dir())
        self.assertFalse((self.root / 'missing.nu').exists())

    @unittest.skipIf(os.name == 'nt', 'POSIX closed-descriptor control')
    def test_stdin_read_failure_is_not_empty_success(self):
        run = self.run_fmt('--check', preexec_fn=lambda: os.close(0))
        self.assertEqual((run.returncode, run.stdout), (2, b''), run.stderr)
        self.assertIn(b'cannot read stdin', run.stderr)

    @unittest.skipUnless(os.name == 'posix' and os.geteuid() != 0, 'POSIX permission control')
    def test_failed_write_releases_source_and_output(self):
        self.path.chmod(0o444)
        self.addCleanup(self.path.chmod, 0o644)
        run = self.run_fmt('--write', self.path)
        self.assertEqual((run.returncode, run.stdout), (2, b''), run.stderr)
        self.assertTrue(run.stderr)
        self.assertEqual(self.path.read_bytes(), RAW)

    def test_nul_source_is_rejected_without_truncating_file(self):
        data = RAW + b'\0// must survive\n'
        self.path.write_bytes(data)
        for args in [('--stdin',), ('--check',), ('--write', self.path), (self.path,)]:
            run = self.run_fmt(*args, data=data)
            self.assertEqual((run.returncode, run.stdout), (2, b''), run.stderr)
            self.assertIn(b'NUL byte', run.stderr)
            self.assertEqual(self.path.read_bytes(), data)

    def test_large_source_has_stable_output(self):
        data = b'// comment\n' * 10000 + RAW
        output = b'// comment\n' * 10000 + CANONICAL
        run = self.run_fmt(data=data)
        self.assertEqual((run.returncode, run.stdout), (0, output), run.stderr)
        self.assertEqual(self.run_fmt('--check', data=output).returncode, 0)

    @unittest.skipIf(os.name == 'nt', 'POSIX compiler driver; native Windows is separate')
    def test_reusable_formatter_releases_tokens_on_every_call(self):
        source = self.root / 'repeat.nu'
        source.write_text('''$ `tools/nurlfmt/format.nu`
@ main → i {
    : String src ( string_from `@ main → i {^0}` )
    : ~ i count 0
    ~ < count 1000 {
        : String out ( format_source src )
        : b ok != 0 ( nurl_str_eq ( string_data out ) `@ main → i { ^ 0 }\\n` )
        ( string_free out )
        ? ! ok { ( string_free src ) ^ 1 } {}
        = count + count 1
    }
    ( string_free src )
    ^ 0
}
''')
        binary = self.root / 'repeat'
        built = subprocess.run([str(ROOT / 'nurl.sh'), '-O1', str(source), str(binary)],
                               cwd=ROOT, capture_output=True, env=self.env, timeout=60)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        if self.env.get('NURL_SAN') == '1':
            definitions = [line for line in binary.with_suffix('.ll').read_text().splitlines()
                           if line.startswith('define ')]
            self.assertTrue(definitions)
            self.assertTrue(all('sanitize_address' in line for line in definitions))
        run = subprocess.run([str(binary)], capture_output=True, env=self.env, timeout=20)
        self.assertEqual((run.returncode, run.stdout, run.stderr), (0, b'', b''))


if __name__ == '__main__':
    unittest.main(verbosity=2)
