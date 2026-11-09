#!/usr/bin/env python3
"""nurl.sh links a library named by its soname where the loader finds it.

WSL keeps the NVIDIA driver's libcuda.so.1 in /usr/lib/wsl/lib, which only
/etc/ld.so.conf.d lists: the dynamic loader finds it, no linker searches it,
and a bare `-l:libcuda.so.1` failed to link a program that would have run
(Agora #503). nurl.sh now links the file the loader's cache (ldconfig -p)
resolves the soname to.

The test needs no GPU. A stand-in libcuda.so.1 (soname and all) is built
into a directory no linker searches, and an `ldconfig` placed first on
PATH reports it the way glibc's does. A program that calls cuInit must
link, record libcuda.so.1 as NEEDED, and run against it. A control with the
cache entry missing must fail to link, which shows the cache is what
found the library.
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

ABI = {'x86_64': 'x86-64', 'aarch64': 'AArch64', 'arm64': 'AArch64',
       'riscv64': 'RISC-V'}.get(platform.machine(), '')

PROGRAM = '''$ `stdlib/core/io.nu`
& `cuda` @ cuInit i32 flags → i32
// The foreign call is vouched for here: it takes and keeps no memory.
unsafe @ cu_init → i { ^ # i ( cuInit # i32 0 ) }
@ main → i {
    ( nurl_println_int ( cu_init ) )
    ^ 0
}
'''

FAKE_CUDA = 'int cuInit(unsigned flags) { return (int)flags + 42; }\n'


@unittest.skipUnless(platform.system() == 'Linux', 'the loader cache is glibc Linux')
@unittest.skipIf(any(Path(p).exists() for p in (
    '/usr/lib/x86_64-linux-gnu/libcuda.so', '/usr/lib/libcuda.so')),
    'a real unversioned libcuda.so is linked as -lcuda before the cache is asked')
class SonameLinkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-soname-link-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)
        cls.clang = os.environ.get('CLANG', 'clang')
        # No blank in the name: ld.so.conf separates entries by whitespace,
        # so no directory the loader's cache knows has one.
        cls.libdir = cls.dir / 'driver_lib'
        cls.libdir.mkdir()
        src = cls.dir / 'fake_cuda.c'
        src.write_text(FAKE_CUDA)
        built = subprocess.run(
            [cls.clang, '-shared', '-fPIC', '-Wl,-soname,libcuda.so.1', str(src),
             '-o', str(cls.libdir / 'libcuda.so.1')], capture_output=True, timeout=120)
        if built.returncode:
            raise RuntimeError(built.stderr.decode(errors='replace'))
        (cls.dir / 'prog.nu').write_text(PROGRAM)

    def fake_ldconfig(self, name, entries):
        bindir = self.dir / name
        bindir.mkdir(exist_ok=True)
        tool = bindir / 'ldconfig'
        lines = ''.join(f'\t{n} (libc6,{ABI}) => {p}\\n' for n, p in entries)
        tool.write_text('#!/bin/sh\n'
                        '[ "$1" = "-p" ] || exit 1\n'
                        f'printf "{len(entries)} libs found in cache\\n{lines}"\n')
        tool.chmod(0o755)
        return bindir

    def build(self, bindir, out):
        env = {k: v for k, v in os.environ.items()
               if k not in ('LIBRARY_PATH', 'LD_LIBRARY_PATH', 'LDFLAGS', 'NURL_GPU_STUBS')}
        env.update({'PATH': f'{bindir}{os.pathsep}{env.get("PATH", "")}',
                    'NURL_STDLIB': str(ROOT), 'NURL_SAN': '0', 'NURL_CACHE': '0',
                    'NURL_SPLIT': '0', 'CLANG': self.clang})
        return subprocess.run([str(ROOT / 'nurl.sh'), str(self.dir / 'prog.nu'), str(out)],
                              cwd=self.dir, env=env, capture_output=True, timeout=300)

    def test_soname_is_linked_where_the_loader_cache_finds_it(self):
        lib = self.libdir / 'libcuda.so.1'
        bindir = self.fake_ldconfig('cache-has-it', [('libcuda.so.1', lib)])
        out = self.dir / 'prog'
        built = self.build(bindir, out)
        log = (built.stdout + built.stderr).decode(errors='replace')
        self.assertEqual(built.returncode, 0, log)
        self.assertIn(str(lib), log)
        dyn = subprocess.run(['readelf', '-d', str(out)], capture_output=True, text=True)
        self.assertIn('[libcuda.so.1]', dyn.stdout)
        self.assertNotIn(str(self.libdir), dyn.stdout, 'no RPATH, no path in NEEDED')
        ran = subprocess.run([str(out)], capture_output=True, timeout=30,
                             env={**os.environ, 'LD_LIBRARY_PATH': str(self.libdir)})
        self.assertEqual(ran.stdout, b'42\n', ran.stderr.decode(errors='replace'))

    def test_without_the_cache_entry_the_bare_soname_does_not_link(self):
        # The driver is there (an unversioned entry says so, so the program
        # is not given the stubs), but the cache has no libcuda.so.1 to link.
        gone = self.dir / 'elsewhere' / 'libcuda.so'
        bindir = self.fake_ldconfig('cache-lacks-it', [('libcuda.so', gone)])
        built = self.build(bindir, self.dir / 'prog_control')
        log = (built.stdout + built.stderr).decode(errors='replace')
        self.assertIn('-l:libcuda.so.1', log)
        self.assertNotEqual(built.returncode, 0, log)


if __name__ == '__main__':
    unittest.main()
