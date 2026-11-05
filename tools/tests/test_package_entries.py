#!/usr/bin/env python3
"""Controls for tools/check_package_entries.py.

The entry selection and verdicts are checked on throwaway package trees
(no compiler needed); the end-to-end cases compile one tiny package with
build/nurlc and are skipped when it has not been built.
"""
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import check_package_entries as cpe  # noqa: E402

NURLC = ROOT / 'build/nurlc'


class Tree(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='nurl-pkgentries-'))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def package(self, d, name, files):
        base = self.root / 'packages' / d
        (base / 'src').mkdir(parents=True)
        (base / 'nurl.toml').write_text(f'[package]\nname = "{name}"\nversion = "0.1.0"\n')
        for rel, text in files.items():
            (base / rel).write_text(text)
        return base


class EntriesTest(Tree):
    def test_program_and_library_entries(self):
        self.package('app', 'app', {'src/main.nu': '', 'src/app.nu': '', 'src/other.nu': ''})
        self.assertEqual(cpe.entries(str(self.root), 'app'), ['main.nu', 'app.nu'])

    def test_a_dash_in_the_name_is_an_underscore_in_the_file(self):
        self.package('http-client', 'http-client', {'src/http_client.nu': ''})
        self.assertEqual(cpe.entries(str(self.root), 'http-client'), ['http_client.nu'])

    def test_the_manifest_name_not_the_directory(self):
        self.package('gRPC', 'grpc', {'src/grpc.nu': ''})
        self.assertEqual(cpe.packages(str(self.root)), [('gRPC', 'grpc')])
        self.assertEqual(cpe.entries(str(self.root), 'gRPC'), ['grpc.nu'])

    def test_a_directory_without_a_manifest_is_not_a_package(self):
        (self.root / 'packages' / 'scratch' / 'src').mkdir(parents=True)
        self.assertEqual(cpe.packages(str(self.root)), [])


class VerdictTest(unittest.TestCase):
    def test_verdicts(self):
        self.assertEqual(cpe.classify(0, ''), 'ok')
        self.assertEqual(cpe.classify(1, 'x.nu:1:1: error: nope'), 'fail')
        self.assertEqual(cpe.classify(1, "stdlib/ext/curl.nu: 'curl' is required but no "
                                         'build-time sentinel …'), 'skip')
        self.assertEqual(cpe.classify(124, 'timed out'), 'fail')

    def test_a_library_gets_a_main_and_a_program_keeps_its_own(self):
        self.assertIn('@ main', cpe.wrapper('lib', 'lib.nu', False))
        self.assertNotIn('@ main', cpe.wrapper('app', 'main.nu', True))
        self.assertTrue(cpe.wrapper('app', 'main.nu', True).startswith('$ `deps/app/src/main.nu`'))


@unittest.skipUnless(NURLC.exists(), 'build/nurlc not built')
class EndToEndTest(Tree):
    def run_one(self, text, clang=None):
        self.package('demo', 'demo', {'src/demo.nu': text})
        cwd = cpe.make_root(str(ROOT), [])
        self.addCleanup(shutil.rmtree, cwd, ignore_errors=True)
        os.symlink(self.root / 'packages' / 'demo', os.path.join(cwd, 'deps', 'demo'))
        return cpe.check_one(str(NURLC), cwd, str(self.root), 'demo', 'demo', 'demo.nu', clang)

    def fake_clang(self, rc, stderr):
        """A clang that answers `rc` and `stderr` to anything (--ir controls)."""
        p = self.root / 'fake-clang'
        p.write_text(f"#!/bin/sh\necho '{stderr}' >&2\nexit {rc}\n")
        p.chmod(0o755)
        return str(p)

    def test_a_library_that_compiles_passes(self):
        self.assertEqual(self.run_one('@ twice i x → i { ^ * 2 x }\n')[2], 'ok')

    def test_a_library_that_does_not_compile_fails(self):
        _, _, verdict, err, _ = self.run_one('@ twice i x → i { ^ ( nope x ) }\n')
        self.assertEqual(verdict, 'fail')
        self.assertIn('nope', err)

    @unittest.skipUnless(shutil.which('clang'), 'no clang')
    def test_ir_a_library_that_lowers_passes(self):
        self.assertEqual(self.run_one('@ twice i x → i { ^ * 2 x }\n', 'clang')[2], 'ok')

    @unittest.skipIf(os.name == 'nt', 'the fake clang is a shell script')
    def test_ir_clang_refusing_the_ir_fails_and_says_so(self):
        clang = self.fake_clang(1, "error: use of undefined value '%r488'")
        _, _, verdict, err, _ = self.run_one('@ twice i x → i { ^ * 2 x }\n', clang)
        self.assertEqual(verdict, 'fail')
        self.assertIn('clang rejected the IR', err)
        self.assertIn('%r488', err)

    @unittest.skipIf(os.name == 'nt', 'the fake clang is a shell script')
    def test_ir_a_frontend_error_is_nurlc_s_and_clang_is_not_asked(self):
        clang = self.fake_clang(1, 'clang must not run')
        _, _, verdict, err, _ = self.run_one('@ twice i x → i { ^ ( nope x ) }\n', clang)
        self.assertEqual(verdict, 'fail')
        self.assertTrue(err.startswith('nurlc: '))
        self.assertNotIn('clang must not run', err)


if __name__ == '__main__':
    unittest.main()
