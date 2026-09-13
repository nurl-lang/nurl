#!/usr/bin/env python3
"""NURL source functions and explicitly external C symbols have separate names."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FunctionLinkageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-function-linkage-')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        self.clang = os.environ.get('CLANG', 'clang')
        self.env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
                    'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                    'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}

    def command(self, args):
        run = subprocess.run([str(x) for x in args], cwd=ROOT, env=self.env,
                             capture_output=True, timeout=120)
        self.assertEqual(run.returncode, 0, (run.stdout + run.stderr).decode(errors='replace'))
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run.stdout

    def compile(self, source, flags=()):
        path = self.directory / 'source.nu'
        path.write_text(source)
        module = self.command([self.compiler, *flags, path])
        ir = self.directory / 'source.ll'
        ir.write_bytes(module)
        return ir, module.decode()

    def execute(self, ir, foreign=None, expected=b''):
        inputs = list(ir) if isinstance(ir, list) else [ir]
        if foreign is not None:
            c = self.directory / 'foreign.c'
            c.write_text(foreign)
            inputs.append(c)
        output = self.directory / 'program'
        self.command([self.clang, '-O2', '-fno-builtin', '-Wno-override-module',
                      *inputs, ROOT / 'stdlib/runtime.native.o', '-lm', '-lpthread',
                      '-ldl', '-o', output])
        self.assertEqual(self.command([output]), expected)

    def test_source_open_and_strlen_coexist_with_real_libc(self):
        source = '''& `c` @ libc_probe → i
@ open i value → i { ^ + value 100 }
@ strlen i value → i { ^ + value 200 }
@ main → i {
    ( nurl_println_int ( open 4 ) )
    ( nurl_println_int ( strlen 5 ) )
    : ( @ i i ) callback \\ i value → i { ^ ( open value ) }
    ( nurl_println_int ( callback 6 ) )
    ( nurl_println `literal @open and @strlen` )
    ^ ( libc_probe )
}
'''
        c = '''#include <fcntl.h>
#include <unistd.h>
#include <string.h>
long libc_probe(void) {
    int fd = open("/dev/null", O_RDONLY);
    if (fd < 0) return 1;
    char byte; int okay = read(fd, &byte, 1) == 0;
    if (close(fd) != 0) return 2;
    return okay && strlen("libc") == 4 ? 0 : 3;
}
'''
        for flags in [(), ('--no-dce',)]:
            with self.subTest(flags=flags):
                ir, module = self.compile(source, flags)
                self.assertIn('define i64 @__nurl_fn.open(', module)
                self.assertIn('define i64 @__nurl_fn.strlen(', module)
                self.assertIn('declare i64  @strlen(', module)
                self.assertNotRegex(module, r'define [^\n]*@(open|strlen)\(')
                self.execute(ir, c, b'104\n205\n106\nliteral @open and @strlen\n')

    def test_strong_foreign_symbol_cannot_interpose_source_function(self):
        ir, module = self.compile('''& `c` @ foreign_probe → i
@ shared_name i x → i { ^ + x 9 }
@ main → i { ^ + - ( shared_name 1 ) 10 ( foreign_probe ) }
''')
        self.assertIn('define i64 @__nurl_fn.shared_name(', module)
        self.execute(ir, '''long shared_name(long value) { return value + 100; }
long foreign_probe(void) { return shared_name(1) == 101 ? 0 : 1; }
''')

    def test_forward_ffi_definition_keeps_literal_c_abi(self):
        ir, module = self.compile('''@ callback i value → i { ^ + value 7 }
& `c` @ callback i value → i
& `c` @ foreign_probe → i
@ main → i { ^ + - ( callback 1 ) 8 ( foreign_probe ) }
''')
        self.assertIn('define i64 @callback(', module)
        self.assertNotIn('@__nurl_fn.callback(', module)
        self.assertNotRegex(module, r'declare [^\n]*@callback\(')
        self.execute(ir, '''extern long callback(long);
long foreign_probe(void) { return callback(2) == 9 ? 0 : 1; }
''')

    def test_keep_roots_preserve_c_entry_without_ffi_declaration(self):
        ir, module = self.compile('''& `c` @ foreign_probe → i
@ callback i value → i { ^ ( internal_helper value ) }
@ internal_helper i value → i { ^ + value 13 }
@ main → i { ^ ( foreign_probe ) }
''', ('--keep=callback',))
        self.assertIn('define i64 @callback(', module)
        self.assertIn('define i64 @__nurl_fn.internal_helper(', module)
        self.execute(ir, '''extern long callback(long);
long foreign_probe(void) { return callback(3) == 16 ? 0 : 1; }
''')

    def test_no_main_module_preserves_external_linkage(self):
        ir, module = self.compile('@ callback i value → i { ^ + value 17 }\n')
        self.assertIn('define i64 @callback(', module)
        self.assertNotIn('@__nurl_fn.callback(', module)
        self.execute(ir, '''extern long callback(long);
int main(void) { return callback(2) == 19 ? 0 : 1; }
''')

    def test_split_definitions_and_references_use_same_symbol(self):
        prefix = self.directory / 'parts'
        increments = '\n'.join('    = value_copy + value_copy 0' for _ in range(200))
        source = '@ open i value → i { : ~ i value_copy value\n' + increments + '\n^ + value_copy 20 }\n'
        ir, module = self.compile(source + '''@ relay i value → i { ^ ( open value: value ) }
@ main → i { ^ - ( relay 4 ) 24 }
''', ('--split=4', '--split-min=1', f'--split-out={prefix}'))
        parts = sorted(self.directory.glob('parts.*.ll'))
        self.assertGreaterEqual(len(parts), 2)
        definition_parts = [p for p in parts if 'define i64 @__nurl_fn.open(' in p.read_text()]
        self.assertEqual(len(definition_parts), 1)
        references = [p for p in parts if 'call i64 @__nurl_fn.open(' in p.read_text()]
        self.assertTrue(any(p != definition_parts[0] for p in references))
        self.assertTrue(any(re.search(r'declare i64 @__nurl_fn\.open\(', p.read_text())
                            for p in references if p != definition_parts[0]))
        self.execute(parts)

    def test_source_debug_names_remain_readable(self):
        ir, module = self.compile('@ open i value → i { ^ + value 1 }\n@ main → i { ^ - ( open 3 ) 4 }\n', ('--g',))
        self.assertIn('define i64 @__nurl_fn.open(', module)
        self.assertIn('!DISubprogram(name: "open"', module)
        self.assertNotIn('!DISubprogram(name: "__nurl_fn.', module)
        self.execute(ir)


if __name__ == '__main__':
    unittest.main()
