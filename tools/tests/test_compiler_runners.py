#!/usr/bin/env python3
"""Fault injection against the real corpus runners in an isolated checkout."""
import os
from pathlib import Path
import shutil
import signal
import shlex
import time
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RunnerTests(unittest.TestCase):
    runners = (False, True)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-runner-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tests = self.root / 'compiler/tests'
        self.tests.mkdir(parents=True)
        (self.tests / 'outputs').mkdir()
        (self.root / 'build').mkdir()
        (self.root / 'stdlib').mkdir()
        for src in (ROOT / 'compiler/tests').glob('*.sh'):
            shutil.copy2(src, self.tests / src.name)
        shutil.copy2(ROOT / 'compiler/tests/run_tests.ps1', self.tests / 'run_tests.ps1')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.script(self.root / 'build/nurlc', '''printf started > "$NURL_COMPILER_STARTED"
if [[ -n ${EXPECTED_FLAG:-} ]]; then
 found=0
 for arg in "$@"; do [[ "$arg" == "$EXPECTED_FLAG" ]] && found=1; done
 [[ "$found" == 1 ]] || exit 2
fi
case "$FAULT" in
  accept|valid) exit 0 ;;
  crash) kill -SEGV $$ ;;
  hang) exec sleep 30 ;;
  error) exit 2 ;;
  worker) kill -KILL "$PPID"; exit 1 ;;
esac
exit 1
''')
        self.script(self.bin / 'nm', 'echo __asan_init\n')
        self.script(self.bin / 'clang', """while [[ $# -gt 0 ]]; do
 if [[ "$1" == -o ]]; then shift; output="$1"; fi
 shift
done
[[ "$output" == /dev/null ]] && exit 0
printf '#!/usr/bin/env bash\nexit "${RUNTIME_CODE:-0}"\n' > "$output"
chmod +x "$output"
""")
        shutil.copy2(self.root / 'build/nurlc', self.root / 'build/nurlc.exe')
        (self.root / 'stdlib/runtime.o').touch()
        self.env = {**os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
                    'CLANG': str(self.bin / 'clang'), 'NURL_SAN': '0',
                    'NURL_TEST_JOBS': '2', 'NURL_SAN_JOBS': '2',
                    'NURL_COMPILE_TIMEOUT': '0.2', 'FAULT': 'reject',
                    'NURL_COMPILER_STARTED': str(self.root / 'compiler-started')}
        self.fixture('should_fail_probe', '@ main → i { ^ 0 }\n')

    def script(self, path, body):
        path.write_text('#!/usr/bin/env bash\nulimit -c 0\n' + body)
        path.chmod(0o755)

    def fixture(self, name, src, gold='COMPILE FAIL\n'):
        (self.tests / f'{name}.nu').write_text(src)
        if gold is not None:
            (self.tests / 'outputs' / f'{name}.txt').write_text(gold)

    def run_runner(self, san, *args, execution_timeout=8):
        if san == 'powershell':
            script = 'run_tests.ps1'
            args = tuple('-Update' if arg == '--update' else arg for arg in args)
            command = [self.env['NURL_TEST_PWSH'], '-NoProfile', '-File', str(self.tests / script), *args]
        else:
            script = 'run_san_tests.sh' if san else 'run_tests.sh'
            command = ['bash', str(self.tests / script), *args]
        started = Path(self.env['NURL_COMPILER_STARTED'])
        started.unlink(missing_ok=True)
        proc = subprocess.Popen(command, env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        # PowerShell's first .NET/runspace startup can exceed the compiler's
        # outer watchdog on a cold runner. Budget startup separately, then
        # enforce the original bound from the fake compiler's entry marker.
        deadline = time.monotonic() + (30 if san == 'powershell' else execution_timeout)
        entered = False
        try:
            while True:
                if not entered and started.is_file():
                    entered = True
                    deadline = time.monotonic() + execution_timeout
                try:
                    stdout, stderr = proc.communicate(timeout=min(0.1, max(0.001, deadline-time.monotonic())))
                    return subprocess.CompletedProcess(command, proc.returncode, stdout, stderr)
                except subprocess.TimeoutExpired as error:
                    if time.monotonic() < deadline:
                        continue
                    phase = 'after compiler entry' if entered else 'before compiler entry'
                    self.fail(f'{script} exceeded outer watchdog {phase}; '
                              f'stdout={error.stdout!r}; stderr={error.stderr!r}')
        finally:
            # Fault injection can kill a worker before its child; cleanup the
            # isolated process group even if the runner already exited.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.communicate()

    def test_valid_rejection(self):
        for san in self.runners:
            with self.subTest(san=san):
                r = self.run_runner(san)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_rejection_without_main(self):
        self.fixture('should_fail_probe', '% Unclosed {\n')
        for san in self.runners:
            with self.subTest(san=san):
                r = self.run_runner(san)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                if san != 'powershell':
                    verdict = self.root / ('build/tests-san' if san else 'build/tests') / '.verdicts'
                    self.assertEqual(verdict.read_text(), 'should_fail_probe PASS\n')
                else:
                    self.assertIn('PASS 1', r.stdout)

    def test_compiler_faults(self):
        for fault in ('accept', 'crash', 'hang', 'error', 'worker'):
            for san in self.runners:
                with self.subTest(fault=fault, san=san):
                    self.env['FAULT'] = fault
                    r = self.run_runner(san, 'should_fail_probe')
                    self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_update_cannot_record_compiler_fault(self):
        for fault in ('accept', 'crash', 'hang', 'error', 'worker'):
            with self.subTest(fault=fault):
                self.env['FAULT'] = fault
                gold = self.tests / 'outputs/should_fail_probe.txt'
                before = gold.read_bytes()
                windows_gold = self.tests / 'outputs-windows/should_fail_probe.txt'
                windows_before = windows_gold.read_bytes() if windows_gold.exists() else None
                r = self.run_runner(self.runners[0], '--update', 'should_fail_probe')
                self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertEqual(gold.read_bytes(), before)
                self.assertEqual(windows_gold.read_bytes() if windows_gold.exists() else None, windows_before)

    def test_selection(self):
        for args in (('missing',), ('should_fail_probe', 'should_fail_probe')):
            for san in self.runners:
                with self.subTest(args=args, san=san):
                    r = self.run_runner(san, *args)
                    self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_compiler_flags(self):
        cases = (
            ('borrow_strict_probe', '--strict-borrowck', 'reject', 'COMPILE FAIL\n'),
            ('arity_strict_probe', '--strict-arity', 'reject', 'COMPILE FAIL\n'),
            ('lint_probe', '--lint', 'valid', 'COMPILE OK\n'),
            ('nobck_probe', '--no-borrowck', 'valid', 'COMPILE OK\nLINK OK\nEXIT 0\nOUTPUT\n'),
        )
        for name, flag, fault, gold in cases:
            self.fixture(name, '@ main → i { ^ 0 }\n', gold)
            self.env.update(EXPECTED_FLAG=flag, FAULT=fault)
            for san in self.runners:
                with self.subTest(name=name, san=san):
                    r = self.run_runner(san, name)
                    self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_fixture_intent(self):
        self.fixture('diag_module_helper', '// fixture: module\n% Partial {\n', None)
        self.fixture('should_fail_real_helper', '% Partial {\n')
        for san in self.runners:
            with self.subTest(san=san):
                r = self.run_runner(san)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn('SKIP', r.stdout)
        self.fixture('diag_module_helper', '// fixture: module\n', 'COMPILE FAIL\n')
        for san in self.runners:
            r = self.run_runner(san)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_runtime_exit(self):
        self.env['FAULT'] = 'valid'
        self.fixture('runtime_probe', '@ main → i { ^ 150 }\n',
                     'COMPILE OK\nLINK OK\nEXIT 150\nOUTPUT\n')
        for code in ('150', '0', '139'):
            self.env['RUNTIME_CODE'] = code
            for san in self.runners:
                with self.subTest(code=code, san=san):
                    r = self.run_runner(san, 'runtime_probe')
                    if code == '150':
                        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                    else:
                        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_verdict_protocol(self):
        xargs = shutil.which('xargs')
        for corruption in ('empty', 'unknown', 'duplicate', 'extra', 'status'):
            self.script(self.bin / 'xargs', f'''"{xargs}" "$@" > "$TMP_VERDICTS"
case "$CORRUPTION" in
 empty) ;;
 unknown) echo 'should_fail_probe MAYBE' ;;
 duplicate) cat "$TMP_VERDICTS" "$TMP_VERDICTS" ;;
 extra) cat "$TMP_VERDICTS"; echo 'unselected PASS' ;;
 status) cat "$TMP_VERDICTS"; exit 1 ;;
esac
''')
            self.env.update(CORRUPTION=corruption, TMP_VERDICTS=str(self.root / 'captured'))
            for san in self.runners:
                with self.subTest(corruption=corruption, san=san):
                    r = self.run_runner(san)
                    self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)


@unittest.skipUnless(os.environ.get('NURL_TEST_PWSH'), 'set NURL_TEST_PWSH to exercise PowerShell on POSIX')
class PowerShellRunnerTests(RunnerTests):
    def test_startup_has_a_separate_budget(self):
        wrapper = self.root / 'slow-pwsh'
        self.script(wrapper, 'sleep 9\nexec ' +
                    shlex.quote(self.env['NURL_TEST_PWSH']) + ' "$@"\n')
        self.env['NURL_TEST_PWSH'] = str(wrapper)
        result = self.run_runner('powershell')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_outer_watchdog_still_catches_an_unbounded_compiler(self):
        self.env.update(FAULT='hang', NURL_COMPILE_TIMEOUT='30')
        with self.assertRaisesRegex(AssertionError, 'outer watchdog after compiler entry'):
            self.run_runner('powershell', execution_timeout=1)

    runners = ('powershell',)

    def test_verdict_protocol(self):
        # Inject worker result objects at the pipeline boundary in a COPY of
        # the runner; keep its real selection, validator and aggregator.
        path = self.tests / 'run_tests.ps1'
        source = path.read_text()
        start = source.index('$updateFlag =')
        end = source.index('# Every selected test must yield')
        good = "[pscustomobject]@{ Name = 'should_fail_probe'; Verdict = 'PASS' }"
        bad = "[pscustomobject]@{ Name = 'should_fail_probe'; Verdict = 'MAYBE' }"
        extra = "[pscustomobject]@{ Name = 'unselected'; Verdict = 'PASS' }"
        for result in ('', bad, good + ',' + good, good + ',' + extra):
            with self.subTest(result=result):
                path.write_text(source[:start] + '$results = @(' + result + ')\n' + source[end:])
                r = self.run_runner('powershell')
                self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == '__main__':
    unittest.main()
