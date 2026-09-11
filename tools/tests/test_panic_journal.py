#!/usr/bin/env python3
"""Public panic-journal contracts through the real runtime, with ASan/LSan."""
import os
import random
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROBE = r'''
#include "stdlib/runtime.c"
#include <assert.h>
static int drops[8];
static int slots[8];
static void dropped(void *p) { ++drops[*(int *)p]; }
static void nested_panic(void *unused) {
    nurl_journal_forget(&slots[0]);
    nurl_journal_push_drop(&slots[1], dropped);
    nurl_panic("inner");
}
static void outer_nested(void *unused) {
    nurl_journal_push_drop(&slots[0], dropped);
    assert(nurl_recover(nested_panic, NULL) == 1);
    assert(drops[0] == 0 && drops[1] == 1);
    nurl_panic("outer");
}
static void nested_success(void *unused) {
    nurl_journal_forget(&slots[0]);
    nurl_journal_push_drop(&slots[1], dropped);
}
static void outer_success(void *unused) {
    nurl_journal_push_drop(&slots[0], dropped);
    assert(nurl_recover(nested_success, NULL) == 0);
    nurl_panic("outer after inner success");
}
static void aliases(void *unused) {
    nurl_journal_push_drop(&slots[0], dropped);
    nurl_journal_push_drop(&slots[0], dropped);
    nurl_journal_push_drop(&slots[1], dropped);
    nurl_journal_push_drop(&slots[1], dropped);
    nurl_journal_forget(&slots[1]);
    nurl_panic("duplicates");
}
static void drop_and_forget(void *p) {
    dropped(p);
    nurl_journal_forget(&slots[0]);
    assert(nurl_recover(nested_panic, NULL) == 1);
}
static void reentrant(void *unused) {
    nurl_journal_push_drop(&slots[0], dropped);
    nurl_journal_push_drop(&slots[2], drop_and_forget);
    nurl_panic("destructor reentry");
}
static void raw_buffers(void *unused) {
    void *p = malloc(128), *q = malloc(64);
    nurl_journal_push(p);
    nurl_journal_push(p);
    nurl_journal_push(q);
    nurl_free(q);
    nurl_panic("raw");
}
static void churn(void *arg) {
    size_t n = *(size_t *)arg;
    int *values = calloc(n * 2, sizeof(int));
    assert(values);
    for (size_t i = 0; i < n; ++i) nurl_journal_push_drop(&values[i], dropped);
    for (size_t i = 0; i < n; ++i) {
        nurl_journal_forget(&values[i]);
        nurl_journal_push_drop(&values[n+i], dropped);
    }
    for (size_t i = n; i < n * 2; ++i) nurl_journal_forget(&values[i]);
    free(values);
}
static void scripted(void *unused) {
    char op;
    int id;
    while (scanf(" %c", &op) == 1) {
        switch (op) {
        case 'P':
            assert(scanf(" %d", &id) == 1 && id >= 0 && id < 8);
            nurl_journal_push_drop(&slots[id], dropped); break;
        case 'F':
            assert(scanf(" %d", &id) == 1 && id >= 0 && id < 8);
            nurl_journal_forget(&slots[id]); break;
        case 'B': nurl_recover(scripted, NULL); break;
        case 'E': return;
        case 'X': nurl_panic("script"); break;
        default: abort();
        }
    }
    abort();
}
int main(int argc, char **argv) {
    for (int i = 0; i < 8; ++i) slots[i] = i;
    assert(argc > 1);
    if (!strcmp(argv[1], "nested-panic")) {
        assert(nurl_recover(outer_nested, NULL) == 1);
        assert(drops[0] == 0 && drops[1] == 1);
    } else if (!strcmp(argv[1], "nested-success")) {
        assert(nurl_recover(outer_success, NULL) == 1);
        assert(drops[0] == 0 && drops[1] == 0);
    } else if (!strcmp(argv[1], "aliases")) {
        assert(nurl_recover(aliases, NULL) == 1);
        assert(drops[0] == 1 && drops[1] == 0);
    } else if (!strcmp(argv[1], "reentrant")) {
        assert(nurl_recover(reentrant, NULL) == 1);
        assert(drops[0] == 0 && drops[1] == 1 && drops[2] == 1);
    } else if (!strcmp(argv[1], "raw")) {
        assert(nurl_recover(raw_buffers, NULL) == 1);
    } else if (!strcmp(argv[1], "churn")) {
        size_t n = argc > 2 ? strtoul(argv[2], NULL, 10) : 8000;
        assert(nurl_recover(churn, &n) == 0);
    } else if (!strcmp(argv[1], "script")) {
        nurl_recover(scripted, NULL);
        for (int i = 0; i < 8; ++i) printf("%d\n", drops[i]);
    } else return 2;
    return 0;
}
'''

class PanicJournalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-journal-')
        cls.addClassCleanup(cls.temp.cleanup)
        source = Path(cls.temp.name)/'probe.c'
        source.write_text(PROBE)
        cls.binary = source.with_suffix('')
        built = subprocess.run(['clang', '-O1', '-g', '-fsanitize=address,undefined',
                        '-fno-sanitize-recover=all', '-I', str(ROOT), str(source),
                        '-lm', '-lpthread', '-ldl', '-o', str(cls.binary)], capture_output=True, timeout=120)
        if built.returncode:
            raise RuntimeError(built.stderr.decode(errors='replace'))

    def check(self, mode):
        run = subprocess.run([str(self.binary), mode], capture_output=True, timeout=30,
            env={**os.environ, 'DEBUGINFOD_URLS': '',
                 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                 'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'})
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertEqual(run.stderr, b'')

    def test_nested_scopes_match_independent_owner_model(self):
        for seed in range(40):
            rng = random.Random(seed)
            frames, commands, expected = [], [], [0] * 8
            def forget(owner):
                for frame in frames:
                    frame[:] = [value for value in frame if value != owner]
            def scope(depth):
                frames.append([])
                for _ in range(40):
                    op = rng.randrange(5 if depth < 3 else 4)
                    owner = rng.randrange(8)
                    if op < 3:
                        commands.append(f'P {owner}')
                        frames[-1].append(owner)
                    elif op == 3:
                        commands.append(f'F {owner}')
                        forget(owner)
                    else:
                        commands.append('B')
                        scope(depth + 1)
                panic = rng.choice([False, True])
                commands.append('X' if panic else 'E')
                if panic:
                    while frames[-1]:
                        owner = frames[-1][-1]
                        expected[owner] += 1
                        forget(owner)
                frames.pop()
            scope(0)
            run = subprocess.run([str(self.binary), 'script'],
                input=('\n'.join(commands)+'\n').encode(), capture_output=True, timeout=30,
                env={**os.environ, 'DEBUGINFOD_URLS': '',
                     'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                     'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'})
            self.assertEqual(run.returncode, 0, (seed, run.stderr))
            self.assertEqual(run.stderr, b'')
            self.assertEqual([int(x) for x in run.stdout.split()], expected, seed)

    def test_inner_panic_after_outer_owner_removed(self): self.check('nested-panic')
    def test_inner_success_after_outer_owner_removed(self): self.check('nested-success')
    def test_duplicate_owners_drop_once_and_forget_all(self): self.check('aliases')
    def test_destructor_can_forget_and_reenter_recovery(self): self.check('reentrant')
    def test_raw_allocations_are_reclaimed_once(self): self.check('raw')
    def test_fifo_churn_with_many_live_owners(self): self.check('churn')

if __name__ == '__main__':
    unittest.main(verbosity=2)
