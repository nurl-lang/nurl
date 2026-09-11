#!/usr/bin/env python3
"""Verify the shared WASI rewriter's output as LLVM, with leak detection."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WasiIrTest(unittest.TestCase):
    def test_parameter_contracts_and_nested_types(self):
        compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        clang = os.environ.get('CLANG', 'clang')
        env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
               'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
               'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}
        san = ['-fsanitize=address,undefined', '-fno-sanitize-recover=all']

        def run(args, cwd=ROOT):
            result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
            return result

        with tempfile.TemporaryDirectory(prefix='nurl-wasi-ir-') as tmp:
            work = Path(tmp)
            runtime = work / 'runtime.o'
            run([clang, '-O1', '-g', *san, '-I', str(ROOT), '-c',
                 str(ROOT / 'stdlib/runtime.c'), '-o', str(runtime)])
            compiled = run([str(compiler), '--sanitize-address', 'tests/ir_test.nu'],
                           ROOT / 'packages/wasmbuilder')
            ir = work / 'test.ll'
            ir.write_bytes(compiled.stdout)
            binary = work / 'test'
            libraries = ['-lm', '-lpthread']
            if sys.platform.startswith('linux'):
                libraries.append('-ldl')
            run([clang, '-O1', *san, str(ir), str(runtime), *libraries, '-o', str(binary)])
            rewritten = run([str(binary), '--emit-ir'])
            self.assertEqual(rewritten.stderr, b'')
            self.assertIn(b'target triple = "wasm32-unknown-wasi"', rewritten.stdout)
            wasm_ir = work / 'rewritten.ll'
            wasm_ir.write_bytes(rewritten.stdout)
            run([clang, '--target=wasm32-wasi', '-c', str(wasm_ir), '-o', str(work / 'wasm.o')])
            self.assertGreater((work / 'wasm.o').stat().st_size, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
