#!/usr/bin/env python3
"""Compile real split and unsplit programs through paths containing spaces."""
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time
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

    def atomic_environment(self, directory):
        return {**os.environ, 'NURL_STDLIB': str(ROOT), 'CLANG': self.clang,
                'NURL_SAN': '0', 'NURL_SPLIT': '0', 'NURL_CACHE': '0',
                'DEBUGINFOD_URLS': '', 'ATOMIC_CONTROL': str(directory)}

    def test_link_publication_preserves_running_binary_and_failed_candidate(self):
        directory = self.directory / 'atomic publication'
        directory.mkdir()
        source = directory / 'source.nu'
        output = directory / 'program [live]'
        env = self.atomic_environment(directory)
        source.write_text('''& `c` @ getchar → i32
@ main → i {
    ( nurl_eprintln `ready` )
    : i32 ignored ( getchar )
    ( nurl_println `old` )
    ^ 0
}
''')
        first = subprocess.run([str(self.toolchain/'nurl.sh'), str(source), str(output)],
                               cwd=directory, env=env, capture_output=True, timeout=120)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        previous = output.read_bytes()
        previous_inode = output.stat().st_ino
        notes = output.with_name(output.name + '.gcno')
        notes.write_bytes(b'previous notes')
        dwarf = output.with_name(output.name + '.dSYM') / 'Contents/Resources/DWARF' / output.name
        dwarf.parent.mkdir(parents=True)
        dwarf.write_bytes(b'previous debug information')
        old = subprocess.Popen([str(output)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: old.poll() is None and old.kill())
        ready, _, _ = select.select([old.stderr], [], [], 10)
        self.assertTrue(ready, 'old executable did not start')
        self.assertEqual(old.stderr.readline(), b'ready\n')
        source.write_text('@ main → i { ( nurl_println `new` ) ^ 0 }\n')
        wrapper = directory/'controlled-clang'
        wrapper.write_text('''#!/usr/bin/env python3
import os, pathlib, subprocess, sys, time
args = sys.argv[1:]
control = pathlib.Path(os.environ['ATOMIC_CONTROL'])
if '-o' in args and any(str(control) in arg and arg.endswith(('.ll', '.o')) for arg in args):
    target = pathlib.Path(args[args.index('-o') + 1])
    target.write_bytes(b'incomplete linker output')
    target.chmod(0o600)
    companion = os.environ.get('ATOMIC_COMPANION', 'new').encode()
    (target.parent/'coverage.gcno').write_bytes(companion + b' notes')
    dwarf = target.with_name(target.name + '.dSYM')/'Contents/Resources/DWARF'/target.name
    dwarf.parent.mkdir(parents=True)
    dwarf.write_bytes(companion + b' debug information')
    (control/'link-started').write_text(str(target))
    deadline = time.monotonic() + 30
    while not (control/'release-link').exists():
        if time.monotonic() >= deadline:
            sys.exit(91)
        time.sleep(.01)
    if (control/'fail-link').exists():
        sys.exit(73)
os.execv(os.environ['ATOMIC_REAL_CLANG'], [os.environ['ATOMIC_REAL_CLANG'], *args])
''')
        wrapper.chmod(0o755)
        controlled = {**env, 'CLANG': str(wrapper),
                      'ATOMIC_REAL_CLANG': shutil.which(self.clang)}
        build = subprocess.Popen([str(self.toolchain/'nurl.sh'), str(source), str(output)],
                                 cwd=directory, env=controlled,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: build.poll() is None and build.kill())
        deadline = time.monotonic() + 30
        while not (directory/'link-started').exists() and build.poll() is None:
            self.assertLess(time.monotonic(), deadline, 'linker control was not reached')
            time.sleep(.01)
        if build.poll() is not None:
            stdout, stderr = build.communicate()
            self.fail(f'linker exited before publication check: {stdout!r} {stderr!r}')
        candidate = Path((directory/'link-started').read_text())
        self.assertNotEqual(candidate, output)
        self.assertEqual(candidate.read_bytes(), b'incomplete linker output')
        self.assertEqual(candidate.name, output.name)
        self.assertEqual(notes.read_bytes(), b'previous notes')
        self.assertEqual(dwarf.read_bytes(), b'previous debug information')
        self.assertEqual(output.read_bytes(), previous)
        self.assertEqual(output.stat().st_ino, previous_inode)
        self.assertTrue(os.access(output, os.X_OK))
        during = subprocess.run([str(output)], input=b'\n', capture_output=True, timeout=10)
        self.assertEqual(during.returncode, 0, during.stderr)
        self.assertEqual(during.stdout, b'old\n')
        (directory/'release-link').touch()
        stdout, stderr = build.communicate(timeout=60)
        self.assertEqual(build.returncode, 0, stdout + stderr)
        self.assertNotEqual(output.stat().st_ino, previous_inode)
        self.assertFalse(candidate.parent.exists())
        self.assertEqual(notes.read_bytes(), b'new notes')
        self.assertEqual(dwarf.read_bytes(), b'new debug information')
        fresh = subprocess.run([str(output)], capture_output=True, timeout=10)
        self.assertEqual(fresh.stdout, b'new\n')
        old_stdout, old_stderr = old.communicate(input=b'\n', timeout=10)
        self.assertEqual(old.returncode, 0, old_stderr)
        self.assertEqual(old_stdout, b'old\n')

        replacement = output.read_bytes()
        replacement_inode = output.stat().st_ino
        (directory/'link-started').unlink()
        (directory/'fail-link').touch()
        failed = subprocess.run([str(self.toolchain/'nurl.sh'), str(source), str(output)],
                                cwd=directory, env=controlled, capture_output=True, timeout=60)
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        self.assertNotIn(b'Done:', failed.stdout)
        failed_candidate = Path((directory/'link-started').read_text())
        self.assertFalse(failed_candidate.parent.exists())
        self.assertEqual(output.read_bytes(), replacement)
        self.assertEqual(output.stat().st_ino, replacement_inode)
        self.assertEqual(subprocess.check_output([str(output)]), b'new\n')
        self.assertEqual(notes.read_bytes(), b'new notes')
        self.assertEqual(dwarf.read_bytes(), b'new debug information')

        # The final executable rename is the commit point. If it fails after
        # complete companions were moved, restore those belonging to the old
        # executable, and still report the failed build.
        (directory/'fail-link').unlink()
        commands = directory/'commands'
        commands.mkdir()
        move = commands/'mv'
        move.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
if pathlib.Path(args[-1]) == pathlib.Path(os.environ['ATOMIC_OUTPUT']):
    sys.exit(74)
os.execv(os.environ['ATOMIC_REAL_MV'], [os.environ['ATOMIC_REAL_MV'], *args])
''')
        move.chmod(0o755)
        publish_env = {**controlled, 'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                       'ATOMIC_OUTPUT': str(output), 'ATOMIC_REAL_MV': shutil.which('mv'),
                       'ATOMIC_COMPANION': 'unpublished'}
        publication = subprocess.run(
            [str(self.toolchain/'nurl.sh'), str(source), str(output)],
            cwd=directory, env=publish_env, capture_output=True, timeout=60)
        self.assertNotEqual(publication.returncode, 0, publication.stdout + publication.stderr)
        self.assertNotIn(b'Done:', publication.stdout)
        self.assertEqual(output.read_bytes(), replacement)
        self.assertEqual(output.stat().st_ino, replacement_inode)
        self.assertEqual(notes.read_bytes(), b'new notes')
        self.assertEqual(dwarf.read_bytes(), b'new debug information')
        self.assertFalse(list(directory.glob('.nurl-link.*')))

        source.write_text('@\n')
        rejected = subprocess.run([str(self.toolchain/'nurl.sh'), str(source), str(output)],
                                  cwd=directory, env=env, capture_output=True, timeout=60)
        self.assertNotEqual(rejected.returncode, 0, rejected.stdout + rejected.stderr)
        self.assertEqual(output.read_bytes(), replacement)
        self.assertEqual(output.stat().st_ino, replacement_inode)
        self.assertEqual(notes.read_bytes(), b'new notes')
        self.assertEqual(dwarf.read_bytes(), b'new debug information')
        self.assertFalse(list(directory.glob('.nurl-link.*')))


if __name__ == '__main__':
    unittest.main(verbosity=2)
