#!/usr/bin/env python3
"""Verify real GCOV line/branch counters from NURL-emitted LLVM IR."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

MAIN = '''$ `helper unit.nu`
@ main → i {
    : i count ? > ( nurl_argc ) 1 3 1
    : ~ i index 0
    ~ < index count {
        ( visit index )
        = index + index 1
    }
    ^ 0
}
'''
HELPER = '''@ visit i index → v {
    ? == index 1 {
        ( nurl_println `middle` )
    } {
        ( nurl_println `edge` )
    }
}
'''


class DriverCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='nurl-coverage-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.base = Path(cls.temporary.name)
        cls.toolchain = cls.base / 'tool chain'
        (cls.toolchain / 'build').mkdir(parents=True)
        shutil.copy2(ROOT / 'nurl.sh', cls.toolchain / 'nurl.sh')
        shutil.copy2(os.environ.get('NURLC_COVERAGE', ROOT / 'build/nurlc'),
                     cls.toolchain / 'build/nurlc')
        (cls.toolchain / 'stdlib').symlink_to(ROOT / 'stdlib', target_is_directory=True)
        cls.env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'NURL_CACHE': '0',
                   'NURL_SPLIT': '8', 'NURL_SAN': '0', 'DEBUGINFOD_URLS': ''}
        cls.clang = os.environ.get('CLANG', 'clang')
        cls.llvm_cov = os.environ.get('LLVM_COV', 'llvm-cov')
        for tool in (cls.clang, cls.llvm_cov):
            if not shutil.which(tool):
                raise RuntimeError(f'required coverage tool missing: {tool}')

    def run_command(self, arguments, cwd):
        result = subprocess.run([str(arg) for arg in arguments], cwd=cwd,
                                env=self.env, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0,
                         (result.stdout + result.stderr).decode(errors='replace'))
        return result

    def project(self, name):
        directory = self.base / name
        directory.mkdir()
        source = directory / 'source "quoted" [unit].nu'
        helper = directory / 'helper unit.nu'
        source.write_text(MAIN)
        helper.write_text(HELPER)
        output = directory / 'program "quoted" \\ ää'
        return directory, source, helper, output

    def report(self, output, report_directory):
        report_directory.mkdir(exist_ok=True)
        self.run_command([self.llvm_cov, 'gcov', '-b', '-c',
                          str(output) + '.gcda'], report_directory)
        reports = {}
        for file in report_directory.glob('*.gcov'):
            content = file.read_text()
            source = next(line.split('Source:', 1)[1] for line in content.splitlines()
                          if 'Source:' in line)
            lines = {}
            for line in content.splitlines():
                parts = line.split(':', 2)
                if len(parts) != 3 or not parts[1].strip().isdigit():
                    continue
                count = parts[0].strip().rstrip('*')
                if count.startswith('#'):
                    lines[int(parts[1])] = 0
                elif count.isdigit():
                    lines[int(parts[1])] = int(count)
            reports[Path(source).name] = (lines, content)
        return reports

    def assert_counters(self, source, helper, output, directory):
        self.assertTrue(Path(str(output) + '.gcno').is_file())
        self.assertFalse(Path(str(output) + '.gcda').exists())
        # Launch away from the compile directory. Embedded absolute profile
        # paths must survive both cwd changes and atomic-link staging cleanup.
        elsewhere = self.base / 'runtime elsewhere'
        elsewhere.mkdir(exist_ok=True)
        first = self.run_command([output], elsewhere)
        self.assertEqual(first.stdout, b'edge\n')
        report = self.report(output, directory / 'first report')
        self.assertEqual(report[helper.name][0][3], 0)
        self.assertEqual(report[helper.name][0][5], 1)
        self.assertEqual(report[source.name][0][4], 1)
        self.assertEqual(report[source.name][0][6], 1)
        self.assertEqual(report[source.name][0][7], 1)
        self.assertIn('taken 0', report[helper.name][1])
        second = self.run_command([output, 'three'], elsewhere)
        self.assertEqual(second.stdout, b'edge\nmiddle\nedge\n')
        report = self.report(output, directory / 'second report')
        self.assertEqual(report[helper.name][0][3], 1)
        self.assertEqual(report[helper.name][0][5], 3)
        self.assertEqual(report[source.name][0][4], 2)
        self.assertEqual(report[source.name][0][6], 4)
        self.assertEqual(report[source.name][0][7], 4)
        self.assertFalse(list(directory.glob('*.link.*')))
        self.assertFalse(list(elsewhere.glob('*.gc*')))

    def check_driver(self, optimization):
        directory, source, helper, output = self.project('project ' + optimization)
        self.run_command([self.toolchain / 'nurl.sh', '--coverage', optimization,
                          source.name, output.name], directory)
        ir = Path(str(output) + '.ll').read_text()
        self.assertIn('!llvm.gcov =', ir)
        self.assertIn('\\22quoted\\22', ir)
        self.assert_counters(source, helper, output, directory)

    def test_unoptimized_counts_and_imported_source(self):
        self.check_driver('-O0')

    def test_optimized_counts_and_imported_source(self):
        self.check_driver('-O2')

    def test_linked_program_ir_remains_relinkable_after_staging_cleanup(self):
        directory, source, helper, output = self.project('persistent linked IR')
        self.run_command([self.toolchain / 'nurl.sh', '--coverage', '-O0',
                          source, output], directory)
        ir = Path(str(output) + '.ll')
        self.assertNotIn('.nurl-link.', ir.read_text())
        self.assertFalse(list(directory.glob('.nurl-link.*')))
        # Rebuild solely from the documented IR artifact after all temporary
        # link inputs and notes have disappeared.
        output.unlink()
        Path(str(output) + '.gcno').unlink()
        self.run_command([self.clang, '-O0', '--coverage', ir,
                          ROOT / 'stdlib/runtime.native.o', '-o', output,
                          '-lm', '-lpthread', '-ldl'], directory)
        self.assert_counters(source, helper, output, directory)

    def test_emit_ir_is_directly_instrumentable(self):
        directory, source, helper, output = self.project('IR only')
        self.run_command([self.toolchain / 'nurl.sh', '--coverage', '--emit-ir',
                          source, output], directory)
        self.assertFalse(output.exists())
        self.assertFalse(Path(str(output) + '.gcno').exists())
        self.run_command([self.clang, '-O0', '--coverage', str(output) + '.ll',
                          ROOT / 'stdlib/runtime.native.o', '-o', output,
                          '-lm', '-lpthread', '-ldl'], directory)
        self.assert_counters(source, helper, output, directory)

    def test_emit_assembly_keeps_instrumentation(self):
        directory, source, helper, output = self.project('assembly only')
        self.run_command([self.toolchain / 'nurl.sh', '--coverage', '--emit-asm',
                          '-O0', source, output], directory)
        self.assertFalse(output.exists())
        self.assertTrue(Path(str(output) + '.gcno').exists())
        self.run_command([self.clang, '--coverage', str(output) + '.s',
                          ROOT / 'stdlib/runtime.native.o', '-o', output,
                          '-lm', '-lpthread', '-ldl'], directory)
        self.assert_counters(source, helper, output, directory)

    def test_debug_without_coverage_has_no_profile(self):
        directory, source, _, output = self.project('debug control')
        self.run_command([self.toolchain / 'nurl.sh', '--debug', source, output], directory)
        self.run_command([output], directory)
        self.assertNotIn('!llvm.gcov', Path(str(output) + '.ll').read_text())
        self.assertFalse(list(directory.glob('*.gc*')))

    def test_failed_link_preserves_previous_notes_and_counters(self):
        directory, source, _, output = self.project('failed coverage link')
        self.run_command([self.toolchain / 'nurl.sh', '--coverage', '-O0',
                          source, output], directory)
        self.run_command([output], directory)
        artifacts = [output, Path(str(output) + '.gcno'), Path(str(output) + '.gcda')]
        previous = {path: path.read_bytes() for path in artifacts}
        source.write_text('@ main → i { ( nurl_println `replacement` ) ^ 0 }\n')
        wrapper = directory / 'fail after clang'
        wrapper.write_text('''#!/usr/bin/env python3
import os, subprocess, sys
result = subprocess.run([os.environ['COVERAGE_REAL_CLANG'], *sys.argv[1:]])
if result.returncode == 0 and any(arg.endswith('.ll') for arg in sys.argv[1:]):
    sys.exit(73)
sys.exit(result.returncode)
''')
        wrapper.chmod(0o755)
        result = subprocess.run(
            [str(self.toolchain / 'nurl.sh'), '--coverage', '-O0', str(source), str(output)],
            cwd=directory, capture_output=True, timeout=120,
            env={**self.env, 'CLANG': str(wrapper),
                 'COVERAGE_REAL_CLANG': shutil.which(self.clang)})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'Done:', result.stdout)
        for path, data in previous.items():
            self.assertEqual(path.read_bytes(), data, str(path))
        self.assertEqual(self.run_command([output], directory).stdout, b'edge\n')
        self.assertFalse(list(directory.glob('.nurl-link.*')))

    def test_empty_output_prefix_is_rejected(self):
        directory, source, _, _ = self.project('invalid prefix')
        result = subprocess.run([str(self.toolchain / 'build/nurlc'), '--coverage=',
                                 str(source)], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b'')
        self.assertIn(b'needs a nonempty output prefix', result.stderr)

    def test_notes_override_requires_coverage(self):
        directory, source, _, _ = self.project('invalid notes override')
        result = subprocess.run([str(self.toolchain / 'build/nurlc'),
                                 '--coverage-notes=/tmp/unused-notes.gcno', str(source)],
                                env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b'')
        self.assertIn(b'requires --coverage=PREFIX', result.stderr)

    def test_staged_coverage_options_require_the_complete_pair(self):
        directory, source, _, output = self.project('incomplete staged options')
        notes = directory / 'staged.gcno'
        link_ir = directory / 'staged.ll'
        for option in [f'--coverage-notes={notes}', f'--coverage-link-ir={link_ir}']:
            with self.subTest(option=option):
                result = subprocess.run(
                    [str(self.toolchain / 'build/nurlc'), f'--coverage={output}',
                     option, str(source)], env=self.env, capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b'')
                self.assertIn(b'--coverage-', result.stderr)
                self.assertFalse(notes.exists())
                self.assertFalse(link_ir.exists())

    def test_check_does_not_emit_staged_link_ir(self):
        directory, source, _, output = self.project('check staged options')
        notes = directory / 'staged.gcno'
        link_ir = directory / 'staged.ll'
        result = self.run_command(
            [self.toolchain / 'build/nurlc', '--check', f'--coverage={output}',
             f'--coverage-notes={notes}', f'--coverage-link-ir={link_ir}', source], directory)
        self.assertEqual(result.stdout, b'')
        self.assertFalse(notes.exists())
        self.assertFalse(link_ir.exists())

    def test_staged_link_ir_write_failure_is_reported(self):
        directory, source, _, output = self.project('failed staged IR output')
        link_ir = directory / 'missing parent' / 'link.ll'
        result = subprocess.run(
            [str(self.toolchain / 'build/nurlc'), f'--coverage={output}',
             f'--coverage-notes={directory / "staged.gcno"}',
             f'--coverage-link-ir={link_ir}', str(source)],
            env=self.env, capture_output=True, timeout=120)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'coverage', result.stderr.lower())
        self.assertFalse(link_ir.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
