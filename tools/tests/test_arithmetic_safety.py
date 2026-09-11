#!/usr/bin/env python3
"""Source arithmetic must reject invalid domains before LLVM UB/poison."""
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = r'''$ `stdlib/std/panic.nu`
& `c` @ from_i i value → i
& `c` @ from_f f value → f
& `c` @ special i which → f
& `c` @ fp_classify f value → i
@ require i got i expected → v {
    ? != got expected { ( panic `wrong result` ) } {}
}
@ expect ( @ v ) action s expected → i {
    : !v PanicInfo result ( recover action )
    : ~ i failed 0
    ?? result {
        T _ → { ? == 0 ( nurl_str_eq expected `` ) { = failed 1 } {} }
        F p → {
            ? == 0 ( nurl_str_eq ( string_data . p msg ) expected ) {
                ( nurl_eprintln ( string_data . p msg ) )
                = failed 1
            } {}
            ( panic_info_free p )
        }
    }
    ? != failed 0 { ( nurl_eprintln ( nurl_str_cat `expected: ` expected ) ) } {}
    ^ failed
}
'''


def integer(value):
    return str(value)


def floating(value):
    if math.isnan(value):
        return '( special 0 )'
    if math.isinf(value):
        return f'( special {1 if value > 0 else 2} )'
    literal = format(abs(value), '.17f')
    if value < 0:
        literal = '- 0.0 ' + literal
    return '( from_f ' + literal + ' )'


def as_signed64(value):
    return (value + 2**63) % 2**64 - 2**63


class ArithmeticSafetyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-arithmetic-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        cls.clang = os.environ.get('CLANG', 'clang')
        cls.san = ['-fsanitize=address,undefined', '-fno-sanitize-recover=all']
        cls.runtime = cls.directory / 'runtime.o'
        cls.env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
                   'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                   'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}
        cls.runtime_normal = cls.directory / 'runtime-normal.o'
        for target, flags in [(cls.runtime, cls.san), (cls.runtime_normal, [])]:
            runtime = subprocess.run([cls.clang, '-O1', '-g', *flags, '-I', str(ROOT),
                '-c', str(ROOT / 'stdlib/runtime.c'), '-o', str(target)],
                capture_output=True, timeout=120)
            if runtime.returncode:
                raise RuntimeError(runtime.stderr.decode(errors='replace'))
        cls.foreign = cls.directory / 'inputs.c'
        cls.foreign.write_text('''#include <math.h>
long long from_i(long long value) { return value; }
double from_f(double value) { return value; }
long long fp_classify(double value) { return isnan(value) ? 2 : isinf(value) ? 1 : 0; }
double special(long long which) { return which == 0 ? NAN : which == 1 ? INFINITY : -INFINITY; }
''')

    def run_cases(self, helpers, cases):
        statements = []
        for expression, expected in cases:
            if isinstance(expected, str):
                body = ': i unused ' + expression
                message = expected
            else:
                body = f'( require {expression} {integer(as_signed64(expected))} )'
                message = ''
            statements.append('    = failed + failed ( expect \\ → v { ' + body +
                              ' } `' + message + '` )\n')
        main = '@ main → i {\n    : ~ i failed 0\n' + ''.join(statements) + \
               '    ? == failed 0 { ( nurl_println `ok` ) } {}\n    ^ failed\n}\n'
        for opt, split, sanitized in [('-O0', False, True), ('-O2', False, False), ('-O2', True, True)]:
            with self.subTest(opt=opt, split=split, sanitized=sanitized):
                source = self.directory / 'input.nu'
                source.write_text(PRELUDE + (main + helpers if opt == '-O2' else helpers + main))
                ir = self.directory / 'input.ll'
                prefix = self.directory / 'part'
                flags = ['--sanitize-address'] if sanitized else []
                if split:
                    flags += ['--no-borrowck', '--split=3', '--split-min=1', f'--split-out={prefix}']
                compile_run = subprocess.run([str(self.compiler), *flags, str(source)],
                    env=self.env, capture_output=True, timeout=120)
                self.assertEqual(compile_run.returncode, 0, compile_run.stderr.decode(errors='replace'))
                ir.write_bytes(compile_run.stdout)
                modules = sorted(self.directory.glob('part.[0-9]*.ll')) if split else [ir]
                self.assertEqual(len(modules), 3 if split else 1)
                binary = self.directory / 'program'
                link_flags = self.san if sanitized else []
                runtime = self.runtime if sanitized else self.runtime_normal
                libraries = ['-lm', '-lpthread']
                if sys.platform.startswith('linux'):
                    libraries.append('-ldl')
                link = subprocess.run([self.clang, opt, '-g', *link_flags, *map(str, modules),
                    str(self.foreign), str(runtime), *libraries, '-o', str(binary)],
                    capture_output=True, timeout=120)
                self.assertEqual(link.returncode, 0, link.stderr.decode(errors='replace'))
                run = subprocess.run([str(binary)], env=self.env, capture_output=True, timeout=60)
                self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
                self.assertEqual(run.stdout, b'ok\n')
                self.assertEqual(run.stderr, b'')

    def test_signed_division_and_remainder_domains(self):
        helpers, cases = '', []
        for width in [8, 16, 32, 64]:
            for op, label in [('/', 'division'), ('%', 'remainder')]:
                name = f'{label}{width}'
                helpers += f'@ {name} i{width} a i{width} b → i {{ ^ # i {op} a b }}\n'
                lo = -(2**(width-1))
                for a, b, expected in [(lo, -1, label+' overflow'), (1, 0, label+' by zero'),
                                       (lo, 1, lo if op == '/' else 0),
                                       (lo+1, -1, -lo-1 if op == '/' else 0)]:
                    cases.append((f'( {name} # i{width} ( from_i {integer(a)} ) '
                                  f'# i{width} ( from_i {integer(b)} ) )', expected))
        self.run_cases(helpers, cases)

    def test_shift_domains_at_each_width_and_signedness(self):
        helpers, cases = '', []
        for width in [8, 16, 32, 64]:
            for signed in [True, False]:
                ty = ('i' if signed else 'u') + str(width)
                for op, label in [('<<', 'left'), ('>>', 'right')]:
                    name = label+ty
                    helpers += f'@ {name} {ty} a {ty} b → i {{ ^ # i {op} a b }}\n'
                    for count in [-1, width, width+1, 0, width-1]:
                        expected = 'shift amount out of range'
                        if 0 <= count < width:
                            expected = 1 << count if op == '<<' else 1 >> count
                            if signed and expected >= 2**(width-1):
                                expected -= 2**width
                        cases.append((f'( {name} # {ty} ( from_i 1 ) '
                                      f'# {ty} ( from_i {integer(count)} ) )', expected))
        self.run_cases(helpers, cases)

    def test_float_cast_domains_and_truncation(self):
        helpers, cases = ': Wrap64 { f value }\n: Wrap32 { f32 value }\n', []
        for fp, wrapper in [('f', 'Wrap64'), ('f32', 'Wrap32')]:
            for width in [8, 16, 32, 64]:
                for signed in [True, False]:
                    ty = ('i' if signed else 'u') + str(width)
                    lo, hi = (-(2**(width-1)), 2**(width-1)) if signed else (0, 2**width)
                    # Adjacent representable input below the exclusive upper bound.
                    if fp == 'f':
                        below = math.nextafter(float(hi), -math.inf)
                    else:
                        bits = struct.unpack('I', struct.pack('f', float(hi)))[0]
                        below = struct.unpack('f', struct.pack('I', bits-1))[0]
                    values = [float(lo), float(lo)-0.9, float(lo)-1.0,
                              math.nextafter(float(lo), -math.inf), below, float(hi), -0.9, -128.9,
                              math.nan, math.inf, -math.inf, -1.0, 0.0, 1e19]
                    for aggregate in [False, True]:
                        name = f'cast_{fp}_{ty}_{int(aggregate)}'
                        value = '@ '+wrapper+' { value }' if aggregate else 'value'
                        helpers += f'@ {name} {fp} value → i {{ ^ # i # {ty} {value} }}\n'
                        for v in values:
                            actual = struct.unpack('f', struct.pack('f', v))[0] if fp == 'f32' else v
                            valid = math.isfinite(actual) and lo <= math.trunc(actual) < hi
                            expected = math.trunc(actual) if valid else 'float-to-integer conversion out of range'
                            cases.append((f'( {name} # {fp} {floating(v)} )', expected))
        self.run_cases(helpers, cases)

    def test_unsigned_division_and_remainder_preserve_high_bits(self):
        helpers, cases = '', []
        for width in [8, 16, 32, 64]:
            for op, label in [('/', 'division'), ('%', 'remainder')]:
                name = f'{label}_u{width}'
                helpers += f'@ {name} u{width} a u{width} b → i {{ ^ # i {op} a b }}\n'
                maximum = 2**width-1
                for b, expected in [(0, label+' by zero'),
                                    (1, maximum if op == '/' else 0),
                                    (-1, 1 if op == '/' else 0)]:
                    cases.append((f'( {name} # u{width} ( from_i -1 ) '
                                  f'# u{width} ( from_i {b} ) )', expected))
        self.run_cases(helpers, cases)

    def test_numeric_guards_preserve_control_flow_and_reclaim_owners(self):
        helpers = r'''@ choose b yes f value → i { ^ ? yes # i value 9 }
@ short b yes f value → i { ^ # i && yes > # i value 0 }
@ allocated f value → i {
    : s text ( nurl_str_cat `live` ` value` )
    ( require ( nurl_str_len text ) 10 )
    ^ # i value
}
'''
        error = 'float-to-integer conversion out of range'
        self.run_cases(helpers, [
            ('( choose T ( from_f 3.9 ) )', 3),
            ('( choose F ( special 0 ) )', 9),
            ('( choose T ( special 0 ) )', error),
            ('( short F ( special 1 ) )', 0),
            ('( short T ( from_f 3.9 ) )', 1),
            ('( short T ( special 1 ) )', error),
            ('( allocated ( from_f 3.9 ) )', 3),
            ('( allocated ( special 0 ) )', error),
        ])

    def test_float_division_and_remainder_keep_ieee_results(self):
        self.run_cases('', [
            ('( fp_classify / ( from_f 1.0 ) ( from_f 0.0 ) )', 1),
            ('( fp_classify / ( from_f 0.0 ) ( from_f 0.0 ) )', 2),
            ('( fp_classify % ( from_f 1.0 ) ( from_f 0.0 ) )', 2),
            ('( fp_classify / ( from_f 2.0 ) ( from_f 1.0 ) )', 0),
        ])

    def test_float_to_bool_is_rejected_for_aggregate_fields_too(self):
        for fp in ['f', 'f32']:
            with self.subTest(fp=fp):
                source = self.directory / 'bad-bool.nu'
                source.write_text(': Wrapped { '+fp+' value }\n@ main → i {\n'
                                  '    : b bad # b @ Wrapped { # '+fp+' 3.5 }\n    ^ 0\n}\n')
                run = subprocess.run([str(self.compiler), '--check', str(source)],
                    env=self.env, capture_output=True, timeout=60)
                self.assertEqual(run.returncode, 1, run.stderr.decode(errors='replace'))
                self.assertIn(b"'# b' of a float value", run.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
