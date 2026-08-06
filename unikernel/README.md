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
| `net/sockets.nu` | the socket ABI (`nurl_tcp_*`, `nurl_udp_*`, `nurl_dns_*`, `nurl_reactor_wait_*`) in NURL, over the sans-IO stack in `stdlib/net/` |
| `boot/` | the guest: PVH entry + long mode + SSE (`boot.S`), the address space (`link.ld`), the machine's bottom edge (`platform_x86.c`), the thread pointer without an auxv (`tls_guest.c`) |
| `build_unikernel.sh` | build a `.nu` into a bootable PVH kernel image |
| `run_qemu.sh` · `run_qemu_tests.sh` | boot one image · run corpus tests inside the guest against their goldens |
| `compile_nu.sh` | compile one program, pulling in `net/sockets.nu` when (and only when) it calls the socket ABI |
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
  PASS         449    corpus tests that build and run with no libc at all
  FAIL           0
  NEEDS-BARE    21    processes and signals — a unikernel has neither
  NEEDS-LIBM     0
  NEEDS-NOLIBC   7    realpath, mkstemp, inotify, execvp, unix sockets
  NEEDS-LIB      4    libsqlite3 x3, libzstd x1 — third-party C libraries
  SKIP         144    compile-fail tests and tests with no standalone build
```

TCP, UDP and name resolution are all in that PASS column. `async_tcp`,
`async_http_server`, `http_server_pool`, `http_server_stop_direct`,
`websocket_client`, `http2_client`, `udp_basic`, `dns_basic`,
`net_basic` and the rest run real clients and real servers against each
other with no kernel sockets anywhere: `unikernel/net/sockets.nu`
implements the socket ABI in NURL over the sans-IO stack, the frames go
around a loopback that is literally "what this stack emits, it
receives", and a blocking read PARKS on its fd — so the scheduler can
still say "nothing can run" and mean it.

What is left in NEEDS-BARE is `fork`/`exec`, signals and the process
API. That is not remaining work in the sense the other columns are: the
plan's non-goals list processes explicitly, and a machine with one
address space has nothing to fork.

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

## It boots

```sh
unikernel/build_unikernel.sh compiler/tests/hello.nu
unikernel/run_qemu.sh build/unikernel/hello.elf     # → Hello, NURL! … exit 0
unikernel/run_qemu_tests.sh                         # 9/9 against the goldens
```

QEMU microvm, PVH direct boot, no BIOS and no bootloader: the
hypervisor reads the ELF note, jumps to `_pvh_start` in 32-bit mode,
and 60 instructions later a NURL program is printing through the
ordinary stdlib path. `net_socket` and `net_tcpstack` are in the guest
gate because they run the whole TCP/UDP stack — connection table,
socket layer, loopback — on bare metal.

Exactly three files differ from the Linux freestanding build, and they
are the ones that talk to the machine: `boot/boot.S`,
`boot/platform_x86.c` and `boot/tls_guest.c` replace
`nolibc/start_x86_64.S`, `nolibc/syscall_linux.c` and
`nolibc/tls_linux.c`. Everything else — nolibc, runtime_core.c,
runtime_bare.c, the NURL program — is the same object code.

Fibers run there too, on stacks whose guard pages are real page-table
entries: the 2 MiB boot mapping is split into 4 KiB pages on demand,
from a page-table pool reserved at boot. The pool is the point — the
version that took a table from the shared bump heap while editing the
mapping of the region that heap lives in faulted inside `nurl_free`.
Splitting now allocates nothing and cannot fail for want of memory;
running out of tables is a panic, because a guard page that quietly
does not exist is the bug the mechanism is for.

The clock is the TSC, and its frequency is never guessed: CPUID leaf
0x40000010 under KVM, or `tsc_khz=` on the kernel command line, or
asking for the time panics. `wallclock=` carries the boot epoch the
same way — a functionality input, not a security control, since the
host already controls the whole image.

## The flagship, so far

```
$ curl --insecure https://127.0.0.1:18443/
hello from a guest over TLS
```

A 369 KiB image, and everything the handshake needs it owns: the
certificate and the key come out of the filesystem baked into it, the
entropy is RDRAND with a panic and no fallback, the clock X.509
validity is checked against arrives on the kernel command line, and the
bytes travel over the pure TCP stack and the virtio-net driver. The
handshake is `stdlib/std/tls.nu` — pure NURL, no libssl, which is why
it links here at all.

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

## What CI watches

Both gates run on every code change (the `unikernel` job):

| | |
|---|---|
| `run_nolibc_tests.sh` | the ordinary corpus, no libc linked — 450 programs against their existing goldens |
| `tests/run_unit_tests.sh` | the differentials, the allocator fuzzer, the scheduler's schedule and its deadlock detector |
| `run_qemu_tests.sh` | the guest: boot, memory, TSC, fibers, the TCP/UDP stack, virtio-net, DHCP, a baked-in filesystem, and two servers answering a client on the host — one plaintext, one TLS 1.3 |

The QEMU job runs under TCG because no runner has `/dev/kvm`. Slower,
identical otherwise — except for the TSC frequency, which no leaf
reports there, so `run_qemu.sh` states it on the kernel command line
the way the plan says the host states the epoch.

A gate that only exists on a developer's machine is a gate that
drifts; this repo has been bitten by that twice (the plan's findings 1
and 11), which is why these are jobs rather than instructions.

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
