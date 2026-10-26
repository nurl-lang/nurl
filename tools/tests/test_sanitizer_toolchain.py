#!/usr/bin/env python3
"""NURL_SAN=1 builds an ASan program or fails; it never builds a silent one.

`zig cc` ships no AddressSanitizer runtime. Asked for
`-fsanitize=address,undefined` it keeps UBSan, drops ASan and exits 0, so on
an installed toolchain (bundled zig) `NURL_SAN=1 nurl.sh` used to publish a
binary in which a use-after-free ran clean (agora #126). These tests stand
in for zig with a wrapper that does exactly that over the system clang.
"""
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
UAF = ROOT / 'tools/tests/sanitizers/heap_uaf.nu'
CLANG = shutil.which(os.environ.get('CLANG', 'clang'))
# A real zig, where there is one (the CI image has it at /opt/zig).
ZIG = next((z for z in (os.environ.get('NURL_TEST_ZIG'), '/opt/zig/zig', shutil.which('zig'))
            if z and os.access(z, os.X_OK)), None)
SAN_CFLAGS = ['-O1', '-g', '-fsanitize=address,undefined',
              '-fsanitize-address-use-after-scope', '-fno-omit-frame-pointer',
              '-fno-sanitize-recover=all']

# A compiler driver that forwards to clang with every ASan flag taken out and
# UBSan left in, as `zig cc` does; it logs each call when $LOG is set.
NO_ASAN_CC = '''#!/bin/sh
[ -n "${{LOG:-}}" ] && echo "$*" >> "$LOG"
{drop_cc}
for a; do
    shift
    case "$a" in
        -fsanitize=address,undefined) set -- "$@" -fsanitize=undefined ;;
        -fsanitize=address|-fsanitize-address-use-after-scope) ;;
        *) set -- "$@" "$a" ;;
    esac
done
exec '{clang}' "$@"
'''


def has_asan(path):
    return b'__asan_init' in Path(path).read_bytes()


def write_script(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


@unittest.skipUnless(CLANG, 'needs a system clang with compiler-rt')
class SanitizerToolchainTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-san-toolchain-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.zig = write_script(cls.directory / 'zig/zig', NO_ASAN_CC.format(
            drop_cc='[ "$1" = cc ] && shift', clang=CLANG))
        cls.no_asan_clang = write_script(cls.directory / 'no-asan/clang', NO_ASAN_CC.format(
            drop_cc='', clang=CLANG))
        # One runtime_san.o built the right way, for the tests that need a
        # current, instrumented one to start from.
        cls.good_runtime = cls.directory / 'runtime_san.o'
        cls.compile_runtime(CLANG, cls.good_runtime)
        if not has_asan(cls.good_runtime):
            raise unittest.SkipTest(f'{CLANG} does not instrument with ASan')

    @staticmethod
    def compile_runtime(compiler, output):
        result = subprocess.run(
            [str(compiler), *SAN_CFLAGS, '-c', str(ROOT / 'stdlib/runtime.c'), '-o', str(output)],
            capture_output=True, timeout=600)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))

    def toolchain(self, name):
        """A prefix laid out like an install: its own nurl.sh and stdlib dir,
        so the runtime_san.o it builds or refuses is not the checkout's."""
        prefix = self.directory / name
        (prefix / 'build').mkdir(parents=True)
        (prefix / 'stdlib').mkdir()
        shutil.copy2(ROOT / 'nurl.sh', prefix / 'nurl.sh')
        shutil.copy2(ROOT / 'build/nurlc', prefix / 'build/nurlc')
        for entry in (ROOT / 'stdlib').iterdir():
            if entry.name not in ('runtime_san.o', 'runtime_debug.o'):
                (prefix / 'stdlib' / entry.name).symlink_to(entry)
        return prefix

    def build(self, prefix, env, source=UAF):
        output = prefix / 'program'
        env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'NURL_SAN': '1',
               'NURL_CACHE': '0', 'DEBUGINFOD_URLS': '', **env}
        result = subprocess.run(
            [str(prefix / 'nurl.sh'), '-O0', '--no-borrowck', str(source), str(output)],
            cwd=prefix, env=env, capture_output=True, timeout=600)
        return result, output

    def test_bundled_zig_is_bypassed_and_its_runtime_rebuilt(self):
        prefix = self.toolchain('zig-bundled')
        runtime = prefix / 'stdlib/runtime_san.o'
        # What the bundled zig left behind before #126: newer than every
        # source, UBSan only.
        self.compile_runtime(self.zig, runtime)
        self.assertFalse(has_asan(runtime))
        log = self.directory / 'zig-bundled.log'
        result, output = self.build(prefix, {'NURL_ZIG': str(self.zig), 'CLANG': CLANG,
                                             'LOG': str(log)})
        text = (result.stdout + result.stderr).decode(errors='replace')
        self.assertEqual(result.returncode, 0, text)
        self.assertIn('[runtime-san] rebuilding', text)
        self.assertFalse(log.exists(), f'zig was called: {log.read_text() if log.exists() else ""}')
        self.assertTrue(has_asan(runtime))
        self.assertTrue(has_asan(output))
        run = subprocess.run([str(output)], capture_output=True, timeout=60,
                             env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
        self.assertNotEqual(run.returncode, 0)
        self.assertIn(b'heap-use-after-free', run.stderr)

    @unittest.skipUnless(ZIG, 'no zig to bundle (NURL_TEST_ZIG, /opt/zig/zig or zig on PATH)')
    def test_real_bundled_zig_catches_the_use_after_free(self):
        prefix = self.toolchain('real-zig')
        result, output = self.build(prefix, {'NURL_ZIG': ZIG, 'CLANG': CLANG})
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors='replace'))
        self.assertTrue(has_asan(output))
        run = subprocess.run([str(output)], capture_output=True, timeout=60,
                             env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0'})
        self.assertIn(b'heap-use-after-free', run.stderr)

    def test_bundled_zig_without_clang_stops_with_the_reason(self):
        prefix = self.toolchain('zig-only')
        # Every tool on PATH except a clang (or a cc that is one).
        bin_dir = self.directory / 'zig-only-bin'
        bin_dir.mkdir()
        for directory in os.environ.get('PATH', '').split(os.pathsep):
            if not os.path.isdir(directory):
                continue
            for name in os.listdir(directory):
                if name.startswith('clang') or name == 'cc' or (bin_dir / name).exists():
                    continue
                path = os.path.join(directory, name)
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    (bin_dir / name).symlink_to(path)
        env = {k: v for k, v in os.environ.items() if k != 'CLANG'}
        result, output = self.build(prefix, {**env, 'PATH': str(bin_dir),
                                             'NURL_ZIG': str(self.zig)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'NURL_SAN=1 needs a system clang with compiler-rt', result.stderr)
        self.assertIn(b'bundled zig', result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse((prefix / 'stdlib/runtime_san.o').exists())

    def test_runtime_built_without_asan_is_refused(self):
        prefix = self.toolchain('no-asan-runtime')
        result, output = self.build(prefix, {'NURL_ZIG': str(self.directory / 'none'),
                                             'CLANG': str(self.no_asan_clang)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'built stdlib/runtime_san.o without AddressSanitizer', result.stderr)
        self.assertFalse((prefix / 'stdlib/runtime_san.o').exists())
        self.assertFalse(output.exists())

    def test_program_linked_without_asan_is_not_published(self):
        # The instrumented runtime's __asan_* references fail this link; the
        # driver's own check on the linked binary backs that up. Either way
        # the build fails and publishes nothing.
        prefix = self.toolchain('no-asan-link')
        shutil.copy2(self.good_runtime, prefix / 'stdlib/runtime_san.o')
        result, output = self.build(prefix, {'NURL_ZIG': str(self.directory / 'none'),
                                             'CLANG': str(self.no_asan_clang)})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_ordinary_build_still_uses_the_bundled_zig(self):
        prefix = self.toolchain('zig-plain')
        log = self.directory / 'zig-plain.log'
        result, output = self.build(prefix, {'NURL_SAN': '0', 'NURL_ZIG': str(self.zig),
                                             'LOG': str(log)},
                                    source=ROOT / 'tools/tests/sanitizers/valid.nu')
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors='replace'))
        self.assertTrue(log.exists() and log.read_text().strip(), 'zig was not called')
        run = subprocess.run([str(output)], capture_output=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))


if __name__ == '__main__':
    unittest.main()
