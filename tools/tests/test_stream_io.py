#!/usr/bin/env python3
"""Exercise NURL stream ownership, binary lengths and EOF/error contracts."""
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROBE = r'''$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
: ~ i delivered 0
@ emit ( Vec u ) bytes → i {
    ( write_bytes bytes )
    ( vec_free [u] bytes )
    ^ 0
}
@ emit_terminated !( Vec u ) IoErr result → i {
    ?? result {
        F _ → { ^ 2 }
        T bytes → {
            ? != . ( vec_data [u] bytes ) ( vec_len [u] bytes ) # u 0 {
                ( vec_free [u] bytes ) ^ 3
            } {}
            ^ ( emit bytes )
        }
    }
}
@ main → i {
    : s mode ( nurl_argv 1 )
    : s path ( nurl_argv 2 )
    ? != 0 ( nurl_str_eq mode `nullfile` ) {
        ^ ( emit_terminated ( read_file_bytes # s 0 ) )
    } {}
    ? != 0 ( nurl_str_eq mode `file` ) {
        ^ ( emit_terminated ( read_file_bytes path ) )
    } {}
    ? != 0 ( nurl_str_eq mode `textfile` ) {
        ?? ( read_file path ) {
            F _ → { ^ 2 }
            T text → {
                ( write_bytes @ ( Vec u ) { . text ctl } )
                ( string_free text )
                ^ 0
            }
        }
    } {}
    ? != 0 ( nurl_str_eq mode `chunk` ) {
        ?? ( file_open path ) {
            F _ → { ^ 2 }
            T file → {
                : !( Vec u ) IoErr result ( file_read_chunk file 65536 )
                ( file_close file )
                ?? result { F _ → { ^ 2 } T bytes → { ^ ( emit bytes ) } }
            }
        }
    } {}
    ? != 0 ( nurl_str_eq mode `short` ) {
        ^ ( emit_terminated ( read_to_end \ *u dst i room → i {
            : ~ i count 0
            ~ & < count room & < count 3 < delivered 10001 {
                = . dst count # u % delivered 251
                = delivered + delivered 1
                = count + count 1
            }
            ^ count
        } 1 ) )
    } {}
    ? != 0 ( nurl_str_eq mode `error` ) {
        ^ ( emit_terminated ( read_to_end \ *u dst i room → i {
            ? > delivered 0 { ^ -1 } {}
            = . dst 0 # u 42
            = delivered 1
            ^ 1
        } 1 ) )
    } {}
    ? != 0 ( nurl_str_eq mode `overreport` ) {
        ^ ( emit_terminated ( read_to_end \ *u dst i room → i { ^ + room 1 } 1 ) )
    } {}
    ? != 0 ( nurl_str_eq mode `bytes` ) { ^ ( emit ( read_all_stdin_bytes ) ) } {}
    ? != 0 ( nurl_str_eq mode `line` ) {
        : String header ( read_line )
        : b ok != 0 ( nurl_str_eq ( string_data header ) `header` )
        ( string_free header )
        ? ! ok { ^ 3 } {}
    } {}
    ?? ( read_stdin ) {
        F _ → { ^ 2 }
        T text → {
            ( write_bytes @ ( Vec u ) { . text ctl } )
            ( string_free text )
            ^ 0
        }
    }
}
'''


@unittest.skipIf(os.name == 'nt', 'POSIX compiler driver and pipe controls')
class StreamIOTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='nurl-stream-io-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.root = Path(cls.tmp.name)
        source = cls.root / 'probe.nu'
        source.write_text(PROBE)
        cls.binary = cls.root / 'probe'
        cls.env = {**os.environ, 'NURL_SAN': '1', 'DEBUGINFOD_URLS': '',
                   'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                   'UBSAN_OPTIONS': 'halt_on_error=1'}
        built = subprocess.run([str(ROOT / 'nurl.sh'), '-O1', str(source), str(cls.binary)],
                               cwd=ROOT, capture_output=True, env=cls.env, timeout=60)
        if built.returncode:
            raise RuntimeError((built.stdout + built.stderr).decode(errors='replace'))
        definitions = [line for line in cls.binary.with_suffix('.ll').read_text().splitlines()
                       if line.startswith('define ')]
        if not definitions or not all('sanitize_address' in line for line in definitions):
            raise AssertionError('stream probe is not fully instrumented')

    def run_probe(self, *args, data=b'', **kwargs):
        run = subprocess.run([str(self.binary), *map(str, args)], input=data,
                             capture_output=True, env=self.env, timeout=10, **kwargs)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run

    def test_lengths_boundaries_and_stdio_header_then_body(self):
        for size in [0, 1, 4095, 4096, 4097, 8192, 65537]:
            text = bytes(number % 251 for number in range(size))
            path = self.root / 'binary'
            path.write_bytes(text)
            for args, data in [(('stdin',), text), (('bytes',), text),
                               (('line',), b'header\n' + text), (('file', path), b''),
                               (('textfile', path), b'')]:
                with self.subTest(size=size, args=args):
                    run = self.run_probe(*args, data=data)
                    self.assertEqual((run.returncode, run.stdout, run.stderr), (0, text, b''))

    def test_short_reads_continue_until_zero(self):
        run = self.run_probe('short')
        self.assertEqual((run.returncode, run.stdout, run.stderr),
                         (0, bytes(n % 251 for n in range(10001)), b''))

    def test_partial_error_and_invalid_count_release_buffer(self):
        for mode in ['error', 'overreport', 'nullfile']:
            run = self.run_probe(mode)
            self.assertEqual((run.returncode, run.stdout, run.stderr), (2, b'', b''))

    def test_file_and_stdin_errors_do_not_return_empty_success(self):
        for mode in ['file', 'textfile', 'chunk']:
            for path in [self.root, self.root / 'absent']:
                run = self.run_probe(mode, path)
                self.assertEqual((run.returncode, run.stdout, run.stderr), (2, b'', b''))
        run = self.run_probe('stdin', preexec_fn=lambda: os.close(0))
        self.assertEqual((run.returncode, run.stdout, run.stderr), (2, b'', b''))

    def test_named_pipe_preserves_binary_payload(self):
        fifo = self.root / 'bytes.fifo'
        os.mkfifo(fifo)
        text = bytes(range(256)) * 300
        errors = []
        def write():
            try:
                with fifo.open('wb') as output:
                    output.write(text)
            except Exception as error:
                errors.append(error)
        writer = threading.Thread(target=write, daemon=True)
        writer.start()
        run = self.run_probe('file', fifo)
        writer.join(timeout=5)
        self.assertFalse(writer.is_alive(), 'FIFO writer did not complete')
        self.assertFalse(errors, errors)
        self.assertEqual((run.returncode, run.stdout, run.stderr), (0, text, b''))

    @unittest.skipUnless(Path('/proc/version').exists(), 'Linux procfs control')
    def test_zero_file_size_does_not_mean_empty_content(self):
        path = Path('/proc/version')
        self.assertEqual(path.stat().st_size, 0)
        run = self.run_probe('file', path)
        self.assertEqual((run.returncode, run.stdout, run.stderr), (0, path.read_bytes(), b''))


if __name__ == '__main__':
    unittest.main(verbosity=2)
