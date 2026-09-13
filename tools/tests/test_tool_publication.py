#!/usr/bin/env python3
"""Registry tool installation preserves a working executable on every failure."""
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import unittest

from test_registry_identity import RegistryIdentityTest


class ToolPublicationTest(RegistryIdentityTest):
    def prepare_tool(self, mode='copy'):
        self.package('a', 'tool', extra=[('src/main.nu', b'@ main \xe2\x86\x92 i { ^ 0 }\n')])
        prefix = self.project / 'installed tools'
        self.bindir = prefix / 'bin'
        self.bindir.mkdir(parents=True)
        self.destination = self.bindir / 'tool'
        old = self.project / 'old.c'
        old.write_text('#include <stdio.h>\nint main(void){fputs("ready\\n",stderr); getchar(); puts("old");}\n')
        new = self.project / 'new.c'
        new.write_text('#include <stdio.h>\nint main(void){puts("new");}\n')
        compiler = os.environ.get('CLANG', 'clang')
        subprocess.run([compiler, str(old), '-o', str(self.destination)], check=True, capture_output=True)
        self.new_program = self.project / 'new program'
        subprocess.run([compiler, str(new), '-o', str(self.new_program)], check=True, capture_output=True)
        # ELF/Mach-O tolerate trailing data, which lets copy progress be
        # observed independently of executable size and stdio buffering.
        with self.new_program.open('ab') as stream:
            stream.write(b'\0' * 1048576)
        self.old_bytes = self.destination.read_bytes()
        self.old_inode = self.destination.stat().st_ino
        driver = self.project / 'controlled-builder'
        driver.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys, time
control = pathlib.Path(os.environ['TOOL_CONTROL'])
target = pathlib.Path(sys.argv[2]).resolve()
mode = os.environ['TOOL_BUILD_MODE']
if mode == 'fifo':
    os.mkfifo(target)
    (control/'source-ready').write_text(str(target))
elif mode == 'directory':
    target.mkdir()
elif mode == 'paused':
    identity = os.environ['TOOL_INSTALL_ID']
    pathlib.Path('.installation-owner').write_text(identity)
    (control/('builder-' + identity)).write_text(str(pathlib.Path.cwd()))
    deadline = time.monotonic() + 30
    while not (control/('release-' + identity)).exists():
        if time.monotonic() >= deadline: sys.exit(91)
        time.sleep(.01)
    if pathlib.Path('.installation-owner').read_text() != identity: sys.exit(92)
    shutil.copyfile(control/'new program', target)
else:
    shutil.copyfile(control/'new program', target)
''')
        driver.chmod(0o755)
        self.tool_env = {**self.env, 'NURL_REGISTRY': self.base + '/a/',
                         'NURL_HOME': str(prefix), 'NURL': str(driver),
                         'NURLC': str(self.compiler), 'TOOL_CONTROL': str(self.project),
                         'TOOL_BUILD_MODE': mode}

    def assert_old_preserved(self):
        self.assertEqual(self.destination.read_bytes(), self.old_bytes)
        self.assertEqual(self.destination.stat().st_ino, self.old_inode)
        old = subprocess.run([str(self.destination)], input=b'\n', capture_output=True, timeout=10)
        self.assertEqual(old.returncode, 0, old.stderr)
        self.assertEqual(old.stdout, b'old\n')
        self.assertFalse(list(self.bindir.glob('.nurlpkg-install-*')))

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'requires a FIFO for deterministic partial-copy control')
    def test_partial_copy_keeps_running_tool_until_atomic_replacement(self):
        self.prepare_tool('fifo')
        old = subprocess.Popen([str(self.destination)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: old.poll() is None and old.kill())
        ready, _, _ = select.select([old.stderr], [], [], 10)
        self.assertTrue(ready)
        self.assertEqual(old.stderr.readline(), b'ready\n')
        install = subprocess.Popen([str(self.binary), 'install', 'tool'], cwd=self.project,
                                   env=self.tool_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: install.poll() is None and install.kill())
        deadline = time.monotonic() + 20
        while not (self.project/'source-ready').exists() and install.poll() is None:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(.01)
        if install.poll() is not None:
            self.fail(install.communicate())
        fifo = Path((self.project/'source-ready').read_text())
        writer = subprocess.Popen(['python3', '-c', '''
import pathlib, sys, time
fifo, source, release = map(pathlib.Path, sys.argv[1:])
data = source.read_bytes()
with fifo.open('wb', buffering=0) as stream:
    stream.write(data[:524288])
    deadline = time.monotonic() + 20
    while not release.exists():
        if time.monotonic() >= deadline: sys.exit(91)
        time.sleep(.01)
    stream.write(data[524288:])
''', str(fifo), str(self.new_program), str(self.project/'release-copy')],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: writer.poll() is None and writer.kill())
        deadline = time.monotonic() + 20
        while True:
            candidates = list(self.bindir.glob('.nurlpkg-install-*'))
            if candidates and candidates[0].stat().st_size >= 65536:
                break
            self.assertIsNone(install.poll())
            self.assertLess(time.monotonic(), deadline)
            time.sleep(.01)
        self.assertEqual(self.destination.read_bytes(), self.old_bytes)
        self.assertEqual(self.destination.stat().st_ino, self.old_inode)
        self.assertFalse(os.access(candidates[0], os.X_OK))
        (self.project/'release-copy').touch()
        writer_stdout, writer_stderr = writer.communicate(timeout=20)
        self.assertEqual(writer.returncode, 0, writer_stdout + writer_stderr)
        stdout, stderr = install.communicate(timeout=30)
        self.assertEqual(install.returncode, 0, stdout + stderr)
        self.assertNotIn(b'Sanitizer', stdout + stderr)
        self.assertNotEqual(self.destination.stat().st_ino, self.old_inode)
        self.assertEqual(subprocess.check_output([str(self.destination)]), b'new\n')
        self.assertFalse(list(self.bindir.glob('.nurlpkg-install-*')))
        old_stdout, old_stderr = old.communicate(input=b'\n', timeout=10)
        self.assertEqual(old.returncode, 0, old_stderr)
        self.assertEqual(old_stdout, b'old\n')

    def test_simultaneous_same_name_installs_keep_private_source_trees(self):
        self.prepare_tool('paused')
        staging = self.project / 'shared staging parent'
        staging.mkdir()
        processes = []
        source_directories = []
        second_prefix = self.project / 'second installation'
        try:
            for identity, prefix in [('first', self.bindir.parent), ('second', second_prefix)]:
                env = {**self.tool_env, 'TMPDIR': str(staging),
                       'NURL_HOME': str(prefix), 'TOOL_INSTALL_ID': identity}
                process = subprocess.Popen([str(self.binary), 'install', 'tool'],
                                           cwd=self.project, env=env,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                processes.append(process)
                marker = self.project / ('builder-' + identity)
                deadline = time.monotonic() + 20
                while not marker.exists() and process.poll() is None:
                    self.assertLess(time.monotonic(), deadline, 'builder did not start')
                    time.sleep(.01)
                if process.poll() is not None:
                    self.fail(process.communicate())
                source_directories.append(Path(marker.read_text()))
            first_source, second_source = source_directories
            self.assertNotEqual(first_source, second_source)
            self.assertEqual((first_source / '.installation-owner').read_text(), 'first')
            self.assertEqual((second_source / '.installation-owner').read_text(), 'second')
            self.assertTrue((first_source / 'src/main.nu').is_file())
            self.assertTrue((second_source / 'src/main.nu').is_file())
            (self.project / 'release-first').touch()
            stdout, stderr = processes[0].communicate(timeout=20)
            self.assertEqual(processes[0].returncode, 0, stdout + stderr)
            self.assertFalse(first_source.parent.exists())
            self.assertEqual((second_source / '.installation-owner').read_text(), 'second')
            self.assertEqual(subprocess.check_output([str(self.destination)]), b'new\n')
            (self.project / 'release-second').touch()
            stdout, stderr = processes[1].communicate(timeout=20)
            self.assertEqual(processes[1].returncode, 0, stdout + stderr)
            self.assertEqual(subprocess.check_output([str(second_prefix / 'bin/tool')]), b'new\n')
            self.assertEqual(list(staging.iterdir()), [])
        finally:
            for identity in ['first', 'second']:
                (self.project / ('release-' + identity)).touch()
            for process in processes:
                try:
                    process.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=10)

    def test_source_read_failure_preserves_old_tool(self):
        self.prepare_tool('directory')
        result = self.run_pkg('install', 'tool', env=self.tool_env)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(b'failed to install binary', result.stderr)
        self.assertNotIn(b'installed \xe2\x86\x92', result.stdout)
        self.assert_old_preserved()

    @unittest.skipUnless(sys.platform == 'linux', 'uses Linux symbol interposition for failure control')
    def test_permission_and_rename_failures_preserve_old_tool(self):
        self.prepare_tool()
        source = self.project/'fail-publication.c'
        source.write_text('''#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
int chmod(const char *path, mode_t mode) {
    if (getenv("FAIL_TOOL_CHMOD") && strstr(path, ".nurlpkg-install-")) { errno=EACCES; return -1; }
    int (*real)(const char *,mode_t)=dlsym(RTLD_NEXT,"chmod"); return real(path,mode);
}
int rename(const char *from, const char *to) {
    if (getenv("FAIL_TOOL_RENAME") && strstr(from, ".nurlpkg-install-")) { errno=EACCES; return -1; }
    int (*real)(const char *,const char *)=dlsym(RTLD_NEXT,"rename"); return real(from,to);
}
''')
        library = self.project/'fail-publication.so'
        subprocess.run([os.environ.get('CLANG', 'clang'), '-shared', '-fPIC', str(source),
                        '-ldl', '-o', str(library)], check=True, capture_output=True)
        for fault in ['FAIL_TOOL_CHMOD', 'FAIL_TOOL_RENAME']:
            with self.subTest(fault=fault):
                env = {**self.tool_env, 'LD_PRELOAD': str(library), fault: '1'}
                result = self.run_pkg('install', 'tool', env=env)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(b'failed to install binary', result.stderr)
                self.assertNotIn(b'installed \xe2\x86\x92', result.stdout)
                self.assert_old_preserved()


def load_tests(loader, tests, pattern):
    # Reuse the signed registry fixture, not its separate identity test suite.
    return unittest.TestSuite(ToolPublicationTest(name) for name in ToolPublicationTest.__dict__
                              if name.startswith('test_'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
