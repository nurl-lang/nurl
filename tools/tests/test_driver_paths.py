#!/usr/bin/env python3
"""Compile real split and unsplit programs through paths containing spaces."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DriverPathsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-driver-paths-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.toolchain = cls.directory / 'tool chain'
        (cls.toolchain / 'build').mkdir(parents=True)
        (cls.toolchain / 'stdlib').mkdir()
        shutil.copy2(ROOT / 'nurl.sh', cls.toolchain / 'nurl.sh')
        shutil.copy2(ROOT / 'build/nurlc', cls.toolchain / 'build/nurlc')
        cls.clang = os.environ.get('CLANG', 'clang')
        runtime = subprocess.run(
            [cls.clang, '-O1', '-I', str(ROOT), '-c', str(ROOT / 'stdlib/runtime.c'),
             '-o', str(cls.toolchain / 'stdlib/runtime.o')],
            capture_output=True, timeout=120)
        if runtime.returncode:
            raise RuntimeError(runtime.stderr.decode(errors='replace'))

    def check_build(self, minimum):
        directory = self.directory / f'project {minimum}'
        directory.mkdir()
        source = directory / 'source [literal].nu'
        output = directory / 'program [literal]'
        source.write_text('''$ `stdlib/core/string.nu`
@ main → i {
    ( nurl_println ( nurl_str_cat `live` ` value` ) )
    ^ 0
}
''')
        env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'CLANG': self.clang,
               'NURL_SAN': '0', 'NURL_SPLIT': '2', 'NURL_SPLIT_MIN': str(minimum),
               'NURL_CACHE': '0', 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
               'LSAN_OPTIONS': 'use_stacks=0', 'DEBUGINFOD_URLS': ''}
        build = subprocess.run(
            [str(self.toolchain / 'nurl.sh'), str(source), str(output)],
            cwd=directory, env=env, capture_output=True, timeout=120)
        self.assertEqual(build.returncode, 0,
                         (build.stdout + build.stderr).decode(errors='replace'))
        self.assertNotIn(b'Sanitizer', build.stderr)
        self.assertEqual(b'\xc3\x972' in build.stdout, minimum == 1,
                         build.stdout.decode(errors='replace'))
        self.assertTrue(output.with_name(output.name + '.ll').is_file())
        self.assertFalse(list(directory.glob('*.o')))
        self.assertFalse(list(directory.glob('*.0.ll')))
        run = subprocess.run([str(output)], env=env, capture_output=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertEqual(run.stdout, b'live value\n')

    def test_small_program_keeps_the_complete_split_prefix(self):
        self.check_build(131072)

    def test_forced_split_keeps_each_object_path_intact(self):
        self.check_build(1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
