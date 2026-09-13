#!/usr/bin/env python3
"""Package test/bench verdicts, literal argv and concurrent artifact ownership."""
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

DRIVER = r'''#!/usr/bin/env python3
import json, os
from pathlib import Path
import sys, time
assert len(sys.argv) == 4, sys.argv
option, source, output = sys.argv[1:]
assert option == ('-O0' if source.startswith('tests/') else '-O2'), sys.argv
source = Path(source)
output = Path(output)
fixture = json.loads(source.read_text())
Path('compiler-argv.json').write_text(json.dumps(sys.argv[1:]))
if os.environ.get('RUNNER_BARRIER'):
    Path('ready').write_text(str(output))
    deadline = time.monotonic() + 15
    while not Path(os.environ['RUNNER_BARRIER']).exists():
        if time.monotonic() > deadline:
            raise RuntimeError('barrier was not released')
        time.sleep(.01)
output.with_name(output.name + '.ll').write_text('private compiler sidecar')
if fixture.get('compile_exit'):
    output.write_text('incomplete output must never run')
    sys.exit(fixture['compile_exit'])
output.write_text('#!/usr/bin/env python3\nimport sys\n'
                  + 'sys.stdout.write(' + repr(fixture.get('stdout', '')) + ')\n'
                  + 'sys.stderr.write(' + repr(fixture.get('stderr', '')) + ')\n'
                  + 'sys.exit(' + repr(fixture.get('exit', 0)) + ')\n')
output.chmod(0o700)
'''


@unittest.skipIf(os.name == 'nt', 'POSIX executable fixtures; batch drivers have separate controls')
class PackageRunnersTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='nurl-package-runners-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.scratch = self.base / 'temp $literal & space'
        self.scratch.mkdir()
        self.driver = self.base / 'driver $literal & space'
        self.driver.write_text(DRIVER)
        self.driver.chmod(0o700)
        self.plain_driver = self.base / 'driver'
        self.plain_driver.write_text(DRIVER)
        self.plain_driver.chmod(0o700)
        self.binary = Path(os.environ.get('NURLPKG', ROOT / 'build/nurlpkg')).resolve()
        self.env = {**os.environ, 'NURL_CC': str(self.driver),
                    'TMPDIR': str(self.scratch), 'NURL_NO_UPDATE_CHECK': '1',
                    'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                    'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}

    def project(self, name, command='test', filename='sample.nu', **fixture):
        project = self.base / name
        directory = project / ('tests' if command == 'test' else 'benches')
        directory.mkdir(parents=True)
        source = directory / filename
        source.write_text(json.dumps(fixture))
        return project, source

    def run_package(self, project, command='test'):
        result = subprocess.run([self.binary, command], cwd=project, env=self.env,
                                capture_output=True, text=True, timeout=25)
        self.assertNotIn('Sanitizer', result.stdout + result.stderr)
        self.assertNotIn('runtime error:', result.stdout + result.stderr)
        self.assertFalse(list(self.scratch.glob('nurlpkg-run-*')), 'artifact directory leaked')
        return result

    def test_literal_paths_and_complete_cleanup(self):
        for command in ('test', 'bench'):
            with self.subTest(command=command):
                filename = "case $(touch PWNED);'&.nu"
                project, source = self.project(command, command, filename, stdout='ok\n')
                result = self.run_package(project, command)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                arguments = json.loads((project / 'compiler-argv.json').read_text())
                self.assertEqual(arguments[1], str(source.relative_to(project)))
                output = Path(arguments[2])
                self.assertEqual(output.parent.parent, self.scratch)
                self.assertFalse(output.parent.exists())
                self.assertFalse((project / 'PWNED').exists())

    def test_matching_golden_still_requires_zero_exit(self):
        self.env['NURL_CC'] = str(self.plain_driver)
        project, _ = self.project('failed golden', stdout='matches\n', stderr='failure detail\n', exit=7)
        goldens = project / 'tests/outputs'
        goldens.mkdir()
        (goldens / 'sample.txt').write_text('matches\n')
        result = self.run_package(project)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('(nonzero exit)', result.stdout)
        self.assertIn('failure detail', result.stderr)

    def test_golden_bytes_are_checked_after_success(self):
        self.env['NURL_CC'] = str(self.plain_driver)
        project, _ = self.project('golden control', stdout='actual\n')
        goldens = project / 'tests/outputs'
        goldens.mkdir()
        golden = goldens / 'sample.txt'
        golden.write_text('different\n')
        failed = self.run_package(project)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('(output mismatch)', failed.stdout)
        golden.write_text('actual\n')
        passed = self.run_package(project)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)

    def test_failed_compilation_and_benchmark_exit_fail(self):
        for command in ('test', 'bench'):
            with self.subTest(command=command):
                project, source = self.project('failure ' + command, command, compile_exit=3)
                failed = self.run_package(project, command)
                self.assertNotEqual(failed.returncode, 0)
                self.assertIn('(compile error)', failed.stdout)
                source.write_text(json.dumps({'exit': 4, 'stderr': 'program failed\n'}))
                failed = self.run_package(project, command)
                self.assertNotEqual(failed.returncode, 0)
                self.assertIn('program failed', failed.stderr)

    def test_same_name_concurrent_runs_have_private_artifacts(self):
        self.env['NURL_CC'] = str(self.plain_driver)
        for command in ('test', 'bench'):
            with self.subTest(command=command):
                projects = [self.project(command + str(i), command, stdout=f'{i}\n')[0]
                            for i in range(2)]
                barrier = self.base / ('release-' + command)
                env = {**self.env, 'RUNNER_BARRIER': str(barrier)}
                processes = [subprocess.Popen([self.binary, command], cwd=project, env=env,
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                              text=True) for project in projects]
                try:
                    deadline = time.monotonic() + 15
                    while not all((project / 'ready').exists() for project in projects):
                        if time.monotonic() >= deadline or any(p.poll() is not None for p in processes):
                            self.fail('both package runners did not reach the compile barrier')
                        time.sleep(.01)
                    outputs = [Path((project / 'ready').read_text()) for project in projects]
                    self.assertNotEqual(outputs[0].parent, outputs[1].parent)
                    for output in outputs:
                        self.assertEqual(stat.S_IMODE(output.parent.stat().st_mode), 0o700)
                    barrier.touch()
                    for process in processes:
                        stdout, stderr = process.communicate(timeout=20)
                        self.assertEqual(process.returncode, 0, stdout + stderr)
                        self.assertNotIn('Sanitizer', stdout + stderr)
                    self.assertFalse(list(self.scratch.glob('nurlpkg-run-*')))
                finally:
                    barrier.touch(exist_ok=True)
                    for process in processes:
                        if process.poll() is None:
                            process.kill()
                        process.communicate()


if __name__ == '__main__':
    unittest.main(verbosity=2)
