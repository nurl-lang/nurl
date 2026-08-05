# `unikernel/` — the freestanding target

The pieces a NURL program needs when there is no operating system under
it. Today it holds **nolibc** — the libc subset NURL programs and the
runtime call, including a from-scratch libm — and **runtime_bare.c**,
the cooperative twin of `stdlib/runtime_ffi.c`. The boot shim and the
virtio drivers land here as Track B of the plan proceeds.

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
| `nolibc/` | the libc subset: `string.c`, `malloc.c`, `stdio.c`, `dtoa.c`, `math.c` (+ the generated `math_tables.h`), `misc.c`, `syscall_linux.c`, `tls_linux.c`, `start_x86_64.S`, `setjmp_x86_64.S` |
| `runtime_bare.c` | threads, fibers, sync and entropy for one vCPU with nothing under it |
| `tests/` | the unit gates — differentials against glibc for strings, float formatting and libm; an allocator fuzzer; the scheduler's schedule and its deadlock detector |
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

## State (2026-08-05)

```
  PASS         433    corpus tests that build and run with no libc at all
  FAIL           0
  NEEDS-BARE    34    sockets and the reactor (phase A4), processes, signals
  NEEDS-LIBM     0
  NEEDS-NOLIBC   7    realpath, mkstemp, inotify, execvp, unix sockets
  NEEDS-LIB      4    libsqlite3 x3, libzstd x1 — third-party C libraries
  SKIP         143    compile-fail tests and tests with no standalone build
```

The bucket a blocked test lands in is **measured**, not listed: each
missing symbol is looked up with `nm` in the hosted `stdlib/runtime.o`
and in the shared objects the ordinary link line names, so "the hosted
runtime defines it" — which is precisely what makes it runtime_bare's
job — is a fact about a file rather than an opinion in a script. A
hand-kept list of names is what gated the whole live surface of the
runtime out of CI, twice.

That leaves one real piece of work, `NEEDS-BARE`: the socket seam, which
is phase A4 and the place the sans-IO stack in `stdlib/net/` plugs in.
`NEEDS-LIB` is not work at all — a unikernel does not link libsqlite3 —
and keeping it in its own column stops the backlog looking larger than
it is.

`build/nolibc/results.txt` carries the per-test verdict with the missing
symbols, so the next piece of work reads itself off the output.

A hello-world built this way is a 75 KB static binary that makes **four
syscalls** in its whole life: `execve`, `arch_prctl` (the thread
pointer), one `mmap` (the first allocator arena) and one `write`.

## Accuracy, stated

`nolibc/math.c` is a from-scratch libm and does not claim correct
rounding. What it claims is measured, per function, by
`tests/math_diff.c` against glibc: 1 ulp for `exp`, `log`, `log2`,
`atan`, `hypot`; 2 for `log10`, `sin`, `cos`, `atan2`, `erf`; 3 for
`tan` and for `pow` at ordinary exponents; 12 for `pow` where
`|y*log2|x||` approaches 1000, because the error there is proportional
to the exponent; 6 for `erfc` out where it returns 1e-56.

`sqrt`, `fabs`, `floor`, `ceil`, `trunc` and `round` are bit-identical
to glibc — they are bit operations, not approximations. `cbrt` is
checked against arithmetic instead of against glibc, because glibc's
`cbrt` is the less accurate of the two: it answers 3.0000000000000004
for the cube root of 27, and this one answers 3.

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
