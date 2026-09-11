#!/usr/bin/env python3
"""Require real memory-error detection through NURL's documented driver.

Keep logs/IR under build/sanitizer-controls. A signal or nonzero exit alone is
not detection: each deliberate violation must name the expected ASan class.
"""
import argparse
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/sanitizer-controls'
FIXTURES = ROOT / 'tools/tests/sanitizers'
ENV = {**os.environ, 'NURL_SAN': '1',
       'ASAN_OPTIONS': 'detect_leaks=0:detect_stack_use_after_return=1:symbolize=0:halt_on_error=1',
       'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'}


def run(command, stem, env=ENV):
    result = subprocess.run([str(x) for x in command], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    (OUT / f'{stem}.stdout').write_bytes(result.stdout)
    (OUT / f'{stem}.stderr').write_bytes(result.stderr)
    return result


def main():
    global OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true', help='calibrate a fuzz run with one heap violation and its valid control')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    OUT = Path(tempfile.mkdtemp(prefix='run-', dir=OUT))
    print(f'Artifacts: {OUT}', flush=True)
    cases = [('heap_oob', 'heap-buffer-overflow'), ('valid', None)]
    if not args.quick:
        cases += [('heap_uaf', 'heap-use-after-free'), ('stack_return', 'stack-use-after-return')]
    for name, expected in cases:
        for opt in (('-O0',) if args.quick else ('-O0', '-O2')):
            # Inlining can extend a callee frame to the caller. The stack
            # return control tests the distinct-frame case at O0.
            if name == 'stack_return' and opt == '-O2':
                continue
            stem = name + opt
            exe = OUT / stem
            result = run([ROOT / 'nurl.sh', opt, '--no-borrowck', FIXTURES / f'{name}.nu', exe], stem + '-build')
            if result.returncode:
                raise RuntimeError(f'{stem}: driver failed; see {OUT}')
            result = run([exe], stem)
            if expected:
                if result.returncode == 0 or expected.encode() not in result.stderr:
                    raise RuntimeError(f'{stem}: expected {expected}, exit={result.returncode}; see {OUT}')
            elif result.returncode or result.stderr or result.stdout != b'42\n42\n':
                raise RuntimeError(f'{stem}: valid control failed; see {OUT}')
            print(f'{stem}: {expected or "clean"}', flush=True)

    if args.quick:
        return 0

    # Attributes must survive every module emission path, including the
    # no-main library path and the replicated inline definitions in parts.
    for flags, name in [([], 'default'), (['--no-dce'], 'no-dce'), (['--g'], 'debug'),
                        (['--no-dce', '--split=3', '--split-min=1', f'--split-out={OUT}/part'], 'split')]:
        result = run([ROOT / 'build/nurlc', '--sanitize-address', '--no-borrowck', *flags,
                      FIXTURES / 'valid.nu'], 'ir-' + name)
        if result.returncode:
            raise RuntimeError(f'{name}: IR emission failed')
        modules = [result.stdout]
        if name == 'split':
            parts = sorted(OUT.glob('part.[0-9]*.ll'))
            if len(parts) != 3:
                raise RuntimeError('split control did not produce three parts')
            modules.extend(p.read_bytes() for p in parts)
        for module in modules:
            defs = [line for line in module.splitlines() if line.startswith(b'define ')]
            if not defs or any(b' sanitize_address' not in line for line in defs):
                raise RuntimeError(f'{name}: definition missing sanitizer attribute')
        print(f'IR {name}: all definitions marked', flush=True)
    # Lower/link the parts too: a correct-looking whole module alone is
    # insufficient evidence for the partitioned codegen path.
    clang = os.environ.get('CLANG', 'clang')
    runtime = ROOT / 'stdlib/runtime_san.o'  # produced above by nurl.sh
    libs = ['-lm', '-lpthread']
    if sys.platform.startswith('linux'):
        libs.append('-ldl')
    symbols = subprocess.check_output(['nm', '-u', str(runtime)])
    if b'sqlite3_' in symbols:
        pkg = subprocess.run(['pkg-config', '--libs', 'sqlite3'], capture_output=True, text=True)
        libs += shlex.split(pkg.stdout) if pkg.returncode == 0 else ['-lsqlite3']
    for name, expected in [('heap_oob', 'heap-buffer-overflow'), ('valid', None)]:
        prefix = OUT / ('split-' + name)
        result = run([ROOT / 'build/nurlc', '--sanitize-address', '--no-borrowck', '--no-dce',
                      '--split=3', '--split-min=1', f'--split-out={prefix}', FIXTURES / f'{name}.nu'],
                     'split-' + name + '-emit')
        parts = sorted(OUT.glob(prefix.name + '.[0-9]*.ll'))
        if result.returncode or len(parts) != 3:
            raise RuntimeError(f'{name}: split emission failed')
        exe = OUT / ('split-' + name + '.bin')
        result = run([clang, '-O0', '-fsanitize=address,undefined', *parts, runtime, *libs, '-o', exe],
                     'split-' + name + '-link')
        if result.returncode:
            raise RuntimeError(f'{name}: split link failed; see {OUT}')
        result = run([exe], 'split-' + name + '-run')
        if expected:
            if result.returncode == 0 or expected.encode() not in result.stderr:
                raise RuntimeError(f'{name}: split binary missed {expected}')
        elif result.returncode or result.stderr or result.stdout != b'42\n42\n':
            raise RuntimeError('valid split control failed')
        print(f'split {name}: {expected or "clean"}', flush=True)

    for source in [FIXTURES / 'library.nu', ROOT / 'compiler/tests/trait_order_dyn.nu',
                   ROOT / 'compiler/tests/test_drop.nu', ROOT / 'compiler/tests/simd_dispatch.nu']:
        result = run([ROOT / 'build/nurlc', '--sanitize-address', source], 'ir-' + source.stem)
        defs = [line for line in result.stdout.splitlines() if line.startswith(b'define ')]
        if result.returncode or not defs or any(b' sanitize_address' not in line for line in defs):
            raise RuntimeError(f'{source.name}: generated definition missing instrumentation')
        print(f'IR {source.name}: all {len(defs)} definitions marked', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f'sanitizer-controls: FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
