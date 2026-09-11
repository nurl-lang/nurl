#!/usr/bin/env python3
"""Runtime source readers must preserve bytes and reject incomplete reads."""
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(os.name == 'nt', 'POSIX runtime/pipe controls; native Windows is separate')
class SourceIOTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='nurl-source-io-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.root = Path(cls.tmp.name)
        probe = cls.root / 'probe.c'
        probe.write_text('''#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
extern long long nurl_stream_read(void *, void *, long long);
extern const char *nurl_read_stdin(void);
extern const char *nurl_read_file(const char *path);
#ifdef __GLIBC__
struct input { int calls; int fail; size_t prefix; };
static ssize_t cookie_read(void *raw, char *buf, size_t count) {
    struct input *in = raw;
    switch (in->calls++) {
    case 0:
        if (count < in->prefix) abort();
        memset(buf, 'x', in->prefix);
        return in->prefix;
    case 1: errno = in->fail ? EIO : EINTR; return -1;
    case 2: memcpy(buf, "tail", 4); return 4;
    default: return 0;
    }
}
#endif
int main(int argc, char **argv) {
#ifdef __GLIBC__
    if (argc == 5 && strcmp(argv[1], "--cookie") == 0) {
        struct input in = {0, atoi(argv[3]), (size_t)atoi(argv[4])};
        cookie_io_functions_t ops = {.read = cookie_read};
        FILE *stream = fopencookie(&in, "r", ops);
        if (!stream) return 3;
        if (strcmp(argv[2], "source") == 0) {
            stdin = stream;
            char *text = (char *)nurl_read_stdin();
            fwrite(text, 1, strlen(text), stdout);
            free(text);
        } else {
            char buf[8192];
            long long got = nurl_stream_read(stream, buf, sizeof(buf));
            if (got < 0) { fclose(stream); return 2; }
            fwrite(buf, 1, (size_t)got, stdout);
        }
        fclose(stream);
        return 0;
    }
#endif
    char *text = (char *)(argc == 1 ? nurl_read_stdin() : nurl_read_file(argv[1]));
    size_t length = strlen(text);
    int failed = fwrite(text, 1, length, stdout) != length;
    free(text);
    return failed;
}
''')
        cls.binary = cls.root / 'probe'
        subprocess.run([shutil.which('clang') or 'clang', '-O1', '-g',
                        '-fsanitize=address,undefined', '-ffunction-sections', '-fdata-sections',
                        str(probe), str(ROOT / 'stdlib/runtime_core.c'), '-Wl,--gc-sections',
                        '-lm', '-lpthread', '-ldl', '-o', str(cls.binary)],
                       check=True, capture_output=True, timeout=60)
        cls.env = {**os.environ, 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                   'UBSAN_OPTIONS': 'halt_on_error=1', 'DEBUGINFOD_URLS': ''}

    def run_probe(self, *args, data=b'', **kwargs):
        return subprocess.run([str(self.binary), *map(str, args)], input=data,
                              capture_output=True, env=self.env, timeout=10, **kwargs)

    def test_exact_capacity_boundaries_and_newlines(self):
        for size in [0, 1, 4095, 4096, 4097, 8192, 65537]:
            with self.subTest(size=size):
                text = (b'a\r\nb\n' * (size // 5 + 1))[:size]
                disk = self.root / 'source.nu'
                disk.write_bytes(text)
                for args in [(), (disk,)]:
                    run = self.run_probe(*args, data=text)
                    self.assertEqual(run.returncode, 0, run.stderr)
                    self.assertEqual(run.stdout, text)
                    self.assertEqual(run.stderr, b'')

    def test_named_pipe_is_read_until_eof(self):
        fifo = self.root / 'source.fifo'
        os.mkfifo(fifo)
        text = b'// streamed source\r\n' * 5000
        errors = []
        def write():
            try:
                with fifo.open('wb') as output:
                    output.write(text)
            except Exception as error:
                errors.append(error)
        writer = threading.Thread(target=write, daemon=True)
        writer.start()
        run = self.run_probe(fifo)
        writer.join(timeout=5)
        self.assertFalse(writer.is_alive(), 'FIFO writer did not complete')
        self.assertFalse(errors, errors)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, text)
        self.assertEqual(run.stderr, b'')

    def test_failed_read_never_returns_success(self):
        for run in [self.run_probe(self.root),
                    self.run_probe(preexec_fn=lambda: os.close(0))]:
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(run.stdout, b'')
            self.assertIn(b'cannot read', run.stderr)
            self.assertNotIn(b'AddressSanitizer', run.stderr)

    @unittest.skipUnless(platform.libc_ver()[0] == 'glibc', 'glibc stdio fault injection')
    def test_partial_eintr_is_retried_but_io_errors_are_rejected(self):
        # The cookie makes fread deliver a prefix then fail. 4096 places
        # that failure in the source reader's one-byte capacity lookahead.
        for reader in ['source', 'stream']:
            for prefix in [3, 4096]:
                with self.subTest(reader=reader, prefix=prefix):
                    retry = self.run_probe('--cookie', reader, '0', prefix)
                    self.assertEqual((retry.returncode, retry.stdout, retry.stderr),
                                     (0, b'x' * prefix + b'tail', b''))
                    failure = self.run_probe('--cookie', reader, '1', prefix)
                    self.assertNotEqual(failure.returncode, 0)
                    self.assertEqual(failure.stdout, b'')
                    self.assertNotIn(b'Sanitizer', failure.stderr)

    @unittest.skipUnless(Path('/proc/version').exists(), 'Linux procfs control')
    def test_zero_reported_size_can_have_content(self):
        path = Path('/proc/version')
        self.assertEqual(path.stat().st_size, 0)
        run = self.run_probe(path)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, path.read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
