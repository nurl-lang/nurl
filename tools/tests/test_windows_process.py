#!/usr/bin/env python3
"""Actual Windows argv, batch drivers and installed package runner contracts.

The encoder's memory/error controls also run on POSIX. Execution tests require
native Windows; Wine 9 re-expands %1/%* substitutions contrary to cmd.exe, so
it is not a substitute for the required windows-tests workflow.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROGRAM = '$ `stdlib/core/io.nu`\n@ main → i { ( nurl_println `literal paths ok` ) ^ 0 }\n'


def checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=180, **kwargs)
    if result.returncode:
        raise AssertionError((result.stdout + result.stderr).decode(errors='replace'))
    return result


class EncoderControls(unittest.TestCase):
    def test_actual_encoder_memory_and_rejection_paths(self):
        with tempfile.TemporaryDirectory(prefix='nurl-process-encoder-') as directory:
            output = Path(directory) / ('probe.exe' if os.name == 'nt' else 'probe')
            flags = (['-lws2_32', '-lwinhttp', '-lbcrypt', '-ladvapi32'] if os.name == 'nt'
                     else ['-g', '-fsanitize=address,undefined', '-lpthread', '-ldl', '-lm'])
            checked([os.environ.get('CLANG', 'clang'), '-O1',
                     str(ROOT / 'tools/tests/windows_process_probe.c'), '-o', str(output), *flags])
            result = checked([str(output), 'controls'], env={**os.environ,
                             'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1'})
            self.assertEqual(result.stdout.strip(), b'Windows process encoder controls: ok')


@unittest.skipUnless(os.name == 'nt', 'requires native Windows cmd.exe and process APIs')
class WindowsProcess(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='nurl-windows-process-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.base = Path(cls.temporary.name)
        cls.probe = cls.base / 'probe.exe'
        checked([os.environ.get('CLANG', 'clang'), '-O1',
                 str(ROOT / 'tools/tests/windows_process_probe.c'), '-o', str(cls.probe),
                 '-lws2_32', '-lwinhttp', '-lbcrypt', '-ladvapi32'])
        cls.env = {**os.environ, 'NURL_PROCESS_PROBE': str(cls.probe),
                   'NURL_TEST_VALUE': 'EXPANSION_MUST_NOT_HAPPEN',
                   'NURL_STDLIB': str(ROOT), 'NURL_NO_UPDATE_CHECK': '1',
                   'NURL_ZIG': str(cls.base / 'no-zig.exe')}

    def setUp(self):
        self.directory = self.base / self._testMethodName
        self.directory.mkdir()

    def invoke(self, mode, command, args=(), **kwargs):
        return subprocess.run([str(self.probe), mode, str(command), *map(str, args)],
                              env=kwargs.pop('env', self.env), capture_output=True,
                              timeout=180, **kwargs)

    def expect_args(self, mode, command, args, prefix=()):
        result = self.invoke(mode, command, [*prefix, *args])
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        expected = ''.join(f'{len(arg.encode())}:{arg}\n' for arg in args).encode()
        self.assertEqual(result.stdout.replace(b'\r\n', b'\n'), expected)

    def test_native_executable_never_expands_shell_characters(self):
        target = self.directory / 'native %NURL_TEST_VALUE% & !keep!.exe'
        shutil.copy2(self.probe, target)
        args = ['', 'two words', 'a=b', '%NURL_TEST_VALUE%', '!NURL_TEST_VALUE!',
                '& echo injected', 'x^y', 'quoted"value', 'trailing\\', 'tab\tvalue']
        for mode in ('run', 'spawn'):
            with self.subTest(mode=mode):
                self.expect_args(mode, target, args, prefix=['echo'])

    def test_batch_files_preserve_supported_argv_in_both_process_apis(self):
        args = ['', 'two words', 'a=b', '%NURL_TEST_VALUE%', '%PATH%',
                '!NURL_TEST_VALUE!', '& echo injected', 'x^y', 'trailing\\']
        for extension in ('bat', 'CmD'):
            driver = self.directory / f'driver %NURL_TEST_VALUE% & !keep!.{extension}'
            driver.write_bytes(b'@echo off\r\nsetlocal DisableDelayedExpansion\r\n'
                               b'"%NURL_PROCESS_PROBE%" echo %*\r\n')
            for mode in ('run', 'spawn'):
                with self.subTest(extension=extension, mode=mode):
                    self.expect_args(mode, driver, args)

    def test_batch_rejects_quotes_and_line_breaks_before_execution(self):
        driver = self.directory / 'must-not-run.cmd'
        driver.write_bytes(b'@echo off\r\necho executed>"%~dp0executed"\r\n')
        for arg in ('quote"&echo injected', 'line\nbreak', 'line\rbreak'):
            with self.subTest(arg=repr(arg)):
                result = self.invoke('run', driver, [arg])
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.directory / 'executed').exists())

    def test_extensionless_path_lookup_prefers_native_executables_then_batch(self):
        env = {**self.env, 'PATH': str(self.directory) + os.pathsep + self.env['PATH']}
        for extension in ('bat', 'cmd'):
            driver = self.directory / f'lookup.{extension}'
            driver.write_bytes(b'@echo off\r\nsetlocal DisableDelayedExpansion\r\n'
                               b'"%NURL_PROCESS_PROBE%" echo batch-selected %*\r\n')
            for mode in ('run', 'spawn'):
                result = self.invoke(mode, 'lookup', ['literal'], env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.replace(b'\r\n', b'\n'),
                                 b'14:batch-selected\n7:literal\n')
            native = self.directory / 'lookup.exe'
            shutil.copy2(self.probe, native)
            for mode in ('run', 'spawn'):
                result = self.invoke(mode, 'lookup', ['echo', 'native-selected'], env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.replace(b'\r\n', b'\n'), b'15:native-selected\n')
            native.unlink()
            driver.unlink()

    def test_explicit_shell_preserves_operators_quotes_and_failure_status(self):
        env = {**self.env, 'COMSPEC': str(self.directory / 'not-the-system-shell.exe')}
        quoted = self.directory / 'quoted shell target & !keep!.exe'
        shutil.copy2(self.probe, quoted)
        commands = [
            (f'"{quoted}" echo "two words" & echo second', 0, b'9:two words\nsecond\n'),
            (f'echo pipe-value|"{quoted}" copy', 0, b'pipe-value\n'),
            ('exit /b 23', 23, b''),
            ('', 0, b''),
        ]
        for command, code, stdout in commands:
            result = subprocess.run([str(self.probe), 'shell', command], env=env,
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, code, result.stderr)
            self.assertEqual(result.stdout.replace(b'\r\n', b'\n'), stdout)
        result = subprocess.run([str(self.probe), 'shell', 'nurl_command_that_does_not_exist_7654321'],
                                env=env, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stderr)

    def test_public_process_run_shell_uses_windows_shell_and_output_errors(self):
        prefix = self.toolchain()
        source = self.directory / 'shell.nu'
        source.write_text('''$ `stdlib/std/process.nu`
@ main → i {
    ?? ( process_run_shell `echo first&echo second` ) {
        T out → {
            ( nurl_print ( output_stdout out ) )
            : i status ( output_exit_code out )
            ( output_free out )
            ? != status 0 { ^ 1 } {}
        }
        F _ → { ^ 2 }
    }
    ?? ( process_run_shell `exit /b 23` ) {
        T out → {
            : i status ( output_exit_code out )
            ( output_free out )
            ? != status 23 { ^ 3 } {}
        }
        F _ → { ^ 4 }
    }
    ^ 0
}
''', encoding='utf-8')
        output = self.directory / 'shell result'
        result = self.invoke('run', prefix / 'nurl.bat', [source, output])
        self.assertEqual(result.returncode, 0,
                         (result.stdout + result.stderr).decode(errors='replace'))
        result = checked([str(output.with_name(output.name + '.exe'))])
        self.assertEqual(result.stdout.replace(b'\r\n', b'\n'), b'first\nsecond\n')

    def toolchain(self):
        prefix = self.directory / 'tool chain %NURL_TEST_VALUE% & !keep!'
        (prefix / 'build').mkdir(parents=True)
        (prefix / 'stdlib').mkdir()
        shutil.copy2(ROOT / 'nurl.bat', prefix / 'nurl.bat')
        shutil.copy2(ROOT / 'build/nurlc.exe', prefix / 'build/nurlc.exe')
        shutil.copy2(ROOT / 'stdlib/runtime.o', prefix / 'stdlib/runtime.o')
        return prefix

    def compile_program(self, driver, source, output, flags=(), env=None):
        result = self.invoke('run', driver, [*flags, source, output], env=env or self.env,
                             cwd=self.directory)
        self.assertEqual(result.returncode, 0,
                         (result.stdout + result.stderr).decode(errors='replace'))
        executable = output.with_name(output.name + '.exe')
        result = checked([str(executable)])
        self.assertEqual(result.stdout.strip(), b'literal paths ok')
        self.assertFalse(list(self.directory.glob('*.link.*')))
        return executable

    def test_driver_flags_literal_paths_and_debug_metadata(self):
        prefix = self.toolchain()
        source = self.directory / 'source %NURL_TEST_VALUE% & !keep!.nu'
        source.write_text(PROGRAM, encoding='utf-8')
        output = self.directory / 'output %NURL_TEST_VALUE% & !keep!'
        for optimization in ('-O0', '-O2'):
            with self.subTest(optimization=optimization):
                self.compile_program(prefix / 'nurl.bat', source, output, [optimization, '-g'])
                ir = output.with_name(output.name + '.ll').read_text(encoding='utf-8')
                self.assertIn('!DICompileUnit(', ir)
                self.assertIn('source %NURL_TEST_VALUE% & !keep!.nu', ir)
                pdb = output.with_name(output.name + '.pdb')
                self.assertTrue(pdb.is_file(), 'MSVC debug symbols were deleted with link staging')
                binary = output.with_name(output.name + '.exe').read_bytes()
                record = binary.index(b'RSDS') + 24
                recorded_path = binary[record:binary.index(b'\0', record)]
                self.assertEqual(recorded_path, pdb.name.encode(), 'binary retained a temporary PDB path')
        only_ir = self.directory / 'IR %NURL_TEST_VALUE% & !keep!'
        result = self.invoke('run', prefix / 'nurl.bat', ['--emit-ir', source, only_ir])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(only_ir.with_name(only_ir.name + '.ll').is_file())
        self.assertFalse(only_ir.with_name(only_ir.name + '.exe').exists())

    def test_failed_link_preserves_previous_executable(self):
        prefix = self.toolchain()
        source = self.directory / 'source.nu'
        source.write_text(PROGRAM, encoding='utf-8')
        output = self.directory / 'output & !keep!'
        executable = self.compile_program(prefix / 'nurl.bat', source, output, ['-g'])
        prior = executable.read_bytes()
        pdb = output.with_name(output.name + '.pdb')
        prior_pdb = pdb.read_bytes()
        source.write_text('& `c` @ nurl_missing_link_symbol → i\n'
                          '@ main → i { ^ ( nurl_missing_link_symbol ) }\n', encoding='utf-8')
        result = self.invoke('run', prefix / 'nurl.bat', ['-g', source, output])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(executable.read_bytes(), prior)
        self.assertEqual(pdb.read_bytes(), prior_pdb)
        self.assertFalse(list(self.directory.glob('*.link.*')))

    def test_publication_rejects_existing_directories_without_touching_contents(self):
        prefix = self.toolchain()
        source = self.directory / 'source.nu'
        source.write_text(PROGRAM, encoding='utf-8')
        for extension in ('pdb', 'exe'):
            with self.subTest(extension=extension):
                output = self.directory / f'output {extension} & !keep!'
                executable = self.compile_program(prefix / 'nurl.bat', source, output, ['-g'])
                pdb = output.with_name(output.name + '.pdb')
                regular = executable if extension == 'pdb' else pdb
                prior = regular.read_bytes()
                collision = output.with_name(output.name + '.' + extension)
                collision.unlink()
                collision.mkdir()
                sentinel = collision / 'caller data.txt'
                sentinel.write_bytes(b'must survive a failed publication\n')
                result = self.invoke('run', prefix / 'nurl.bat', ['-g', source, output])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'must be regular files', result.stdout + result.stderr)
                self.assertTrue(collision.is_dir())
                self.assertEqual(sentinel.read_bytes(), b'must survive a failed publication\n')
                self.assertEqual(list(collision.iterdir()), [sentinel])
                self.assertEqual(regular.read_bytes(), prior)
                self.assertFalse(list(self.directory.glob('*.link.*')))

    def test_publication_rejects_linker_directory_outputs(self):
        prefix = self.toolchain()
        source = self.directory / 'source.nu'
        source.write_text(PROGRAM, encoding='utf-8')
        output = self.directory / 'output & !keep!'
        executable = self.compile_program(prefix / 'nurl.bat', source, output, ['-g'])
        pdb = output.with_name(output.name + '.pdb')
        prior_exe, prior_pdb = executable.read_bytes(), pdb.read_bytes()
        backend = self.directory / 'controlled backend.exe'
        shutil.copy2(self.probe, backend)
        shutil.copy2(prefix / 'stdlib/runtime.o', prefix / 'stdlib/runtime.mingw.o')
        for mode in ('output-directory', 'pdb-directory'):
            with self.subTest(mode=mode):
                env = {**self.env, 'NURL_ZIG': str(backend), 'NURL_PROCESS_LINK_CONTROL': mode}
                result = self.invoke('run', prefix / 'nurl.bat', ['-g', source, output], env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'must be regular files', result.stdout + result.stderr)
                self.assertEqual(executable.read_bytes(), prior_exe)
                self.assertEqual(pdb.read_bytes(), prior_pdb)
                self.assertFalse(list(self.directory.glob('*.link.*')))

    def test_upgrade_aliases_forward_arguments_without_a_second_shell_parse(self):
        prefix = self.toolchain()
        shutil.copy2(self.probe, prefix / 'build/nurlpkg.exe')
        args = ['--check', '--version', 'v0.65.0', '--force']
        expected = ''.join(f'{len(arg)}:{arg}\n' for arg in ['self-update', *args]).encode()
        for alias in ('upgrade', 'update', 'self-update', 'self-upgrade'):
            with self.subTest(alias=alias):
                result = self.invoke('run', prefix / 'nurl.bat', [alias, *args])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.replace(b'\r\n', b'\n'), expected)

    def test_package_test_and_bench_use_literal_batch_driver_arguments(self):
        prefix = self.toolchain()
        project = self.directory / 'project %NURL_TEST_VALUE% & !keep!'
        scratch = self.directory / 'scratch %NURL_TEST_VALUE% & !keep!'
        project.mkdir()
        scratch.mkdir()
        for folder in ('tests', 'benches'):
            (project / folder).mkdir()
            (project / folder / 'case %NURL_TEST_VALUE% & !keep!.nu').write_text(PROGRAM, encoding='utf-8')
        env = {**self.env, 'NURL_CC': str(prefix / 'nurl.bat'), 'TEMP': str(scratch),
               'TMP': str(scratch)}
        for command in ('test', 'bench'):
            with self.subTest(command=command):
                result = subprocess.run([str(ROOT / 'build/nurlpkg.exe'), command], cwd=project,
                                        env=env, capture_output=True, timeout=180)
                self.assertEqual(result.returncode, 0,
                                 (result.stdout + result.stderr).decode(errors='replace'))
                self.assertFalse(list(scratch.glob('nurlpkg-run-*')))

    def test_installed_shims_preserve_literal_paths(self):
        prefix = self.directory / 'installed %NURL_TEST_VALUE% & !keep!'
        env = {**self.env, 'NURL_HOME': str(prefix),
               'NURL_BUNDLE_ZIG': str(self.directory / 'no-zig')}
        env.pop('NURL_STDLIB', None)
        result = self.invoke('run', ROOT / 'tools/install-toolchain.bat', env=env)
        self.assertEqual(result.returncode, 0,
                         (result.stdout + result.stderr).decode(errors='replace'))
        source = self.directory / 'source %NURL_TEST_VALUE% & !keep!.nu'
        source.write_text(PROGRAM, encoding='utf-8')
        output = self.directory / 'installed output %NURL_TEST_VALUE% & !keep!'
        self.compile_program(prefix / 'bin/nurl.bat', source, output, env=env)
        for tool in ('nurlc', 'nurlpkg'):
            result = self.invoke('run', prefix / f'bin/{tool}.bat', ['--version'], env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = checked([str(ROOT / f'build/{tool}.exe'), '--version'], env=env)
            self.assertEqual(result.stdout, expected.stdout)
        # The installed package runner defaults to bare `nurl` on PATH.
        project = self.directory / 'installed consumer'
        (project / 'tests').mkdir(parents=True)
        (project / 'tests/case %NURL_TEST_VALUE% & !keep!.nu').write_text(PROGRAM, encoding='utf-8')
        env = {**env, 'PATH': str(prefix / 'bin') + os.pathsep + env['PATH']}
        env.pop('NURL_CC', None)
        env.pop('NURL', None)
        result = self.invoke('run', prefix / 'bin/nurlpkg.bat', ['test'], cwd=project, env=env)
        self.assertEqual(result.returncode, 0,
                         (result.stdout + result.stderr).decode(errors='replace'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
