# `unikernel/` — the freestanding target

The pieces a NURL program needs when there is no operating system under
it. Today it holds **nolibc**, the libc subset the runtime calls; the
boot shim, `runtime_bare.c` and the virtio drivers land here as Track B
of the plan proceeds.

## Why it lives in this repo

Decided by coupling, not convenience:

- the target layer is **toolchain**, peer to the Windows/wasm/RISC-V
  targets that already live here;
- `nolibc/` and `stdlib/runtime_core.c` are a hand-synced pair — the
  header of every file in `nolibc/` is written against the *measured*
  undefined-symbol set of `runtime_core.o`, so a runtime change that
  adds a libc call must break this directory's gate **in the same PR**,
  not silently weeks later in another repo;
- the gate is a compiler-CI gate by construction: it builds the ordinary
  test corpus.

## What is here

| | |
|---|---|
| `nolibc/` | the libc subset: `string.c`, `malloc.c`, `stdio.c`, `dtoa.c`, `misc.c`, `syscall_linux.c`, `tls_linux.c`, `start_x86_64.S`, `setjmp_x86_64.S` |
| `tests/` | the unit gates — string and float-format differentials against glibc, and an allocator fuzzer |
| `build_nolibc.sh` | build one `.nu` program against nolibc with `-nostdlib` |
| `run_nolibc_tests.sh` | build and run the **whole corpus** that way |

## The rule this directory is built on

Everything in `nolibc/` is portable C except three files:
`syscall_linux.c`, `start_x86_64.S` and `setjmp_x86_64.S`. The
unikernel target replaces the first (writes go to a UART, reads come
from a baked-in image) and the second (the boot shim enters at
`kmain`), and keeps everything else byte-for-byte. So the Linux
`-nostdlib` build is not a toy: it is the same code the guest will run,
with a different bottom edge, which is what makes testing it on Linux
worth anything.

## State (2026-08-04)

```
  PASS       339      corpus tests that build and run with no libc at all
  NEEDS-FFI  139      call into runtime_ffi — sockets, threads, processes.
                      That list is the remaining A3 work, measured.
  SKIP       143      compile-fail tests and tests with no standalone build
  FAIL         0
```

`build/nolibc/results.txt` carries the per-test verdict, and every
`NEEDS-FFI` line names the symbols that were missing, so the next piece
of work reads itself off the output rather than out of a plan.

A hello-world built this way is a 75 KB static binary that makes **four
syscalls** in its whole life: `execve`, `arch_prctl` (the thread
pointer), one `mmap` (the first allocator arena) and one `write`.

## Running the gates

```sh
unikernel/tests/run_unit_tests.sh        # string / float-format / allocator
unikernel/run_nolibc_tests.sh            # the corpus, with no libc
unikernel/build_nolibc.sh prog.nu        # one program
```

## What is deliberately missing

`nolibc` refuses rather than pretends. `opendir` returns NULL,
`isatty` answers 0, `tcgetattr` fails, `backtrace` finds no frames —
each is the honest answer for a target with no filesystem, no terminal
and no unwinder, and each makes the caller take its already-written
error path. None of them succeeds while doing nothing, which is how a
stub becomes someone else's bug report months later.
