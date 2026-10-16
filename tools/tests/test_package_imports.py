#!/usr/bin/env python3
"""Controls for tools/check_package_imports.sh on throwaway package trees.

The script cds to its own repository root, so each case copies it into a
temporary tree (no Git: the exported-tree inventory) beside a packages/
directory written for that case.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tools/check_package_imports.sh'


@unittest.skipUnless(shutil.which('bash'), 'Bash required')
class PackageImportsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nurl-pkgimports-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        shutil.copy(SCRIPT, self.root / 'tools/check_package_imports.sh')
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        # Keep Git from finding an enclosing checkout of the temp directory.
        self.env['GIT_CEILING_DIRECTORIES'] = str(self.root.parent)

    def package(self, name, deps=(), files=None):
        base = self.root / 'packages' / name
        base.mkdir(parents=True)
        if deps is not None:
            lines = ['[package]', f'name = "{name}"', 'version = "0.1.0"', '', '[dependencies]']
            lines += [f'{d} = {{ path = "../{d}", version = "^0" }}' for d in deps]
            (base / 'nurl.toml').write_text('\n'.join(lines) + '\n')
        for rel, text in (files or {}).items():
            path = base / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        return base

    def run_check(self):
        return subprocess.run(['bash', str(self.root / 'tools/check_package_imports.sh')],
                              cwd=self.root, env=self.env, capture_output=True, text=True,
                              timeout=60)

    def assert_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('every deps/ import declared', result.stdout)

    def assert_refuses(self, *needles):
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for needle in needles:
            self.assertIn(needle, result.stderr)
        return result.stderr

    def test_declared_dependency_passes(self):
        self.package('app', deps=['gpu'], files={
            'src/main.nu': '$ `deps/gpu/src/gpu.nu`\n@ main → i { ^ 0 }\n'})
        self.assert_passes()

    def test_undeclared_dependency_in_src_is_refused(self):
        # objdet 0.4.4: imported deps/gpu, declared only onnx and image.
        self.package('objdet', deps=['onnx', 'image'], files={
            'src/detect.nu': '$ `deps/onnx/src/onnx.nu`\n$ `deps/gpu/src/gpu.nu`\n'})
        err = self.assert_refuses("packages/objdet/src/detect.nu:2:",
                                  "'gpu' is not in packages/objdet/nurl.toml")
        self.assertNotIn("'onnx'", err)

    def test_nested_src_and_indented_imports_count(self):
        self.package('app', deps=[], files={
            'src/sub/inner.nu': '\t$\t`deps/tensor/src/tensor.nu`\n'})
        self.assert_refuses("packages/app/src/sub/inner.nu:1:", "'tensor'")

    def test_package_root_source_counts(self):
        # The packer ships the root's *.nu as source too.
        self.package('app', deps=[], files={'lib.nu': '$ `deps/http/src/http.nu`\n'})
        self.assert_refuses("packages/app/lib.nu:1:", "'http'")

    def test_tests_and_examples_are_not_packaged_sources(self):
        self.package('app', deps=[], files={
            'tests/t.nu': '$ `deps/http/src/http.nu`\n',
            'examples/e.nu': '$ `deps/http/src/http.nu`\n'})
        self.assert_passes()

    def test_documented_import_in_a_comment_is_not_an_import(self):
        # packages/http's header documents its own import line.
        self.package('http', deps=[], files={
            'src/http.nu': '// Usage:\n//     $ `deps/http/src/http.nu`\n@ f → i { ^ 0 }\n'})
        self.assert_passes()

    def test_directory_without_manifest_is_skipped(self):
        self.package('scratch', deps=None, files={'src/x.nu': '$ `deps/gpu/src/gpu.nu`\n'})
        self.assert_passes()

    def test_self_import_through_packages_still_refused(self):
        self.package('torchpt', deps=[], files={
            'src/main.nu': '$ `packages/torchpt/src/pickle.nu`\n'})
        self.assert_refuses("may not import through a 'packages/…' path",
                            'packages/torchpt/src/main.nu:1:')

    def test_both_rules_report_together(self):
        self.package('app', deps=[], files={
            'src/main.nu': '$ `packages/app/src/x.nu`\n$ `deps/gpu/src/gpu.nu`\n'})
        self.assert_refuses("'packages/…' path", "'gpu' is not in packages/app/nurl.toml")

    def test_unreadable_manifest_fails_loudly(self):
        base = self.package('app', deps=None, files={'src/main.nu': '$ `deps/gpu/src/gpu.nu`\n'})
        (base / 'nurl.toml').write_text('[package\nname = \n')
        self.assert_refuses('cannot read packages/app/nurl.toml')


if __name__ == '__main__':
    unittest.main()
