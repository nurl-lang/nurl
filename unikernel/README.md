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
| `boot/` | the guest: PVH entry + long mode + SSE + the interrupt stubs (`boot.S`), the address space (`link.ld`), the machine's bottom edge (`platform_x86.c`), the pages themselves (`pagealloc.c`), the baked-in filesystem (`initfs.c`), the thread pointer without an auxv (`tls_guest.c`) |
| `drivers/` | `virtionet.nu` — frames in and out over a real device |
| `build_unikernel.sh` | build a `.nu` into a bootable PVH kernel image |
| `run_qemu.sh` · `run_qemu_tests.sh` | boot one image · run corpus tests inside the guest against their goldens |
| `compile_nu.sh` | compile one program, pulling in `net/sockets.nu` when (and only when) it calls the socket ABI |
| `demos/` | the programs that only make sense in the guest: devices, DHCP, a filesystem, a server, an MCP endpoint, TLS — and the two that are about failure, `fault.nu` and `soak.nu` |
| `tests/` | the unit gates — differentials against glibc for strings, float formatting and libm; two allocator fuzzers; the scheduler's schedule and its deadlock detector |
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

## State (2026-08-06)

```
  PASS         451    corpus tests that build and run with no libc at all
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
unikernel/run_qemu_tests.sh                         # 18/18 against the goldens
```

QEMU microvm, PVH direct boot, no BIOS and no bootloader: the
hypervisor reads the ELF note, jumps to `_pvh_start` in 32-bit mode,
and 60 instructions later a NURL program is printing through the
ordinary stdlib path. `net_socket` and `net_tcpstack` are in the guest
gate because they run the whole TCP/UDP stack — connection table,
socket layer, loopback — on bare metal.

Exactly three files REPLACE anything from the Linux freestanding build,
and they are the ones that talk to the machine: `boot/boot.S`,
`boot/platform_x86.c` and `boot/tls_guest.c` stand in for
`nolibc/start_x86_64.S`, `nolibc/syscall_linux.c` and
`nolibc/tls_linux.c`. Two more are additions with no hosted counterpart,
because on Linux the kernel already did the job: `boot/pagealloc.c` (the
pages) and `boot/initfs.c` (a filesystem inside the image). Everything
else — nolibc, runtime_core.c, runtime_bare.c, the NURL program — is the
same object code.

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

## When it does not boot, and when it breaks

A guest is the only program with nobody underneath it to explain what
went wrong, which is why this is a section and not a footnote.

Every CPU exception is caught. The IDT is installed before anything that
could fault — the very first thing after the serial port — and its 256
stubs reach one handler that prints the fault by the name every manual
uses, with the registers that say where it happened:

```
nurl: fault #PF page fault vector=14 err=0x2
  rip=0x10be42 rsp=0x128000 rflags=0x6
  cr2=0x127ff8 (not present) on write
  rax=0x18 rbx=0x18 rcx=0x1488a0 rdx=0x0
  rsi=0x18 rdi=0x18 rbp=0x0
```

Without that, all of these were the same event: the machine stopped, the
hypervisor exited, and the exit sentinel was simply missing — which from
the host is indistinguishable from a clean, successful run. The version
of this directory before it could not tell a null dereference from a
finished program.

`#DF` and `#PF` are delivered on an **IST stack**, because the fault most
worth surviving is a stack that ran off its guard page: delivered on
that same dead stack, the push faults, the double fault's push faults,
and the machine triple-faults with nothing printed.

Two guard pages exist for the same reason:

- **under the boot stack** — a recursion off the end used to write into
  whatever `.bss` put underneath and carry on with someone else's
  variables. Coroutine stacks always had one; the stack `main` runs on
  did not.
- **page zero** — the boot tables identity-map the low 4 GiB present and
  writable, so a store through a null pointer QUIETLY SUCCEEDED in this
  guest while being a segfault on every hosted target. It is unmapped
  once the hypervisor's handover block and command line are known to be
  elsewhere, which they always are.

`demos/fault.nu` causes both on purpose and the gate reads the reports —
including the exit code, because these are distinguishable states:

| exit | what happened |
|---|---|
| 0…125 | the program's own `main` returned it |
| 126 | a CPU exception. A fault report precedes it |
| 127 | `pf_panic` — the machine refused to continue, and said why: no memory map, no TSC frequency, no entropy source, out of page tables |
| 134 | `abort` — the runtime's own, e.g. `nurl: out of memory` |
| 124 | no exit sentinel at all: the guest never finished. A hang, or a hypervisor that killed it |

The sentinel is the protocol, not the exit status: Firecracker cannot
hand a guest's exit code back at all, so `[nurl-exit] N` on the serial
port is what the harness parses and `isa-debug-exit` is a cross-check.

## Memory, and how much of it there is

The hypervisor's memory map is READ, never assumed — the largest usable
region at or above the image is the heap, and a guest told it has less
RAM than it guessed is a guest that corrupts itself. Out of that region:
a page-table pool reserved at boot (64 tables, enough to split 128 MiB
into 4 KiB pages, which is about 1900 coroutine stacks), and everything
else belongs to `boot/pagealloc.c`.

That file is what `mmap` and `munmap` are made of here, and it gives
memory BACK: a sorted free list of page ranges, best fit, coalescing on
both sides, with the tail rolled back when a freed range touches it. The
version before it was a bump pointer and a `munmap` that returned
success without doing anything, which is fine for a program that runs
once and wrong for the thing this target is for. Measured on a 256 MiB
machine: allocate a megabyte and free it, and the old one died on the
251st iteration. The current one survives 4000.

It is portable C on purpose. `tests/pagealloc_fuzz.c` runs it on the
host against a model that checks, on every operation, that no two live
ranges overlap, that the accounting agrees, and that after freeing
everything the region fits in itself — a page allocator only ever
exercised inside a virtual machine is one whose bugs arrive as a triple
fault.

Above it, nolibc's `malloc` keeps per-class free lists carved from 1 MiB
arenas. Those arenas are never returned, by design: a program's small
objects settle at a plateau and handing pages back and forth around it
would trade a bounded high-water mark for churn. So the shape to expect
from a long-running guest is *live memory rises to a plateau and stays
there*, which is exactly what `demos/soak.nu` asserts about itself over
200 requests, and what the same demo reported as a 5 MB climb when the
virtio-net driver was still leaking a buffer per packet.

Exhaustion is a refusal, then an honest death: `pa_alloc` answers zero,
`malloc` answers NULL, and the runtime prints `nurl: out of memory
(requested N bytes)` and aborts. It is not a silent wild write, which is
what it was until `nl_map` was made to answer the way its Linux twin
always had.

## Running one in production

**What the image needs.** Nothing but a hypervisor with virtio-mmio and
a serial port. No disk, no initrd, no bootloader, no kernel command line
beyond the keys below, no filesystem except the one baked into the ELF.

**The kernel command line** is a contract, and every key is stated
rather than guessed:

| key | meaning | when it is required |
|---|---|---|
| `tsc_khz=N` | the TSC frequency | when no CPUID leaf reports one — i.e. under TCG. Asking for the time without it PANICS rather than inventing a number |
| `wallclock=N` | the boot epoch, seconds | whenever X.509 validity is checked: TLS client verification, and a server whose certificate has dates |
| `virtio_mmio.device=…` | where the devices are | appended by the hypervisor; the guest parses it, and a guest with no match reports "no device" rather than probing blindly |
| `args="…"` | the program's argv | when the program takes arguments. ONE key, quoted, because QEMU appends its own entries after `-append` and a program that read the tail of the line would be handed them |

**How small it goes.** Measured, by asking QEMU for less and less until
the answer stopped coming:

| | |
|---|---|
| `hello` | answers on **3 MiB** |
| the HTTP server, over virtio-net and DHCP | answers on **4 MiB** |
| the HTTPS server, TLS 1.3 with an RSA-2048 certificate | answers on **4 MiB** |
| below that | it SAYS so: 3 MiB of TLS is `nurl: out of memory (requested 24 bytes)` and an abort; 2 MiB is `the hypervisor reported no usable memory above the image` and exit 127 |

A fiber is the one thing that makes a program's appetite jump: each one
costs **68 KiB** — a 64 KiB stack and a 4 KiB guard page — so a program
holding 500 of them needs 34 MiB before anything else. Asking for more
than the machine can hold is an abort with a count (`cannot create a
fiber — out of memory for its stack (11 live)`), not a program that
quietly runs eleven of them and reports what the eleven did.

The gates run with 256 MiB, which hides that question entirely, so
`run_qemu_tests.sh` also boots `hello` on 4 MiB and the server on 8 —
headroom over the floor, because what is worth pinning is appetite, and
a change that doubles what the guest needs should fail here rather than
on somebody's Firecracker host.

**Sizes and limits**, all of them deliberate and all of them checkable:

| | |
|---|---|
| vCPUs | one. Fibers are cooperative; there is no preemption and no SMP |
| memory | whatever the hypervisor reports; 256 MiB is what the gates run with, 4 MiB is what a server needs (see above) |
| MTU | 1500. Frames are refused above 2036 bytes rather than truncated |
| IP fragments | dropped, counted, never reassembled. A datagram over the MTU does not arrive |
| open files | 16, from the baked-in archive, read-only |
| sockets | the fd table in `stdlib/net/socket.nu`; ephemeral ports are per-protocol, TCP and UDP have separate spaces |
| name resolution | literals and `localhost`. Anything else is refused, not guessed |
| processes, signals | none. `fork`/`exec` report unsupported; there is one address space and nothing to fork |
| GPU | none in a microVM; a swarm node advertises CPU-wasm capability only |

**Building and running one:**

```sh
unikernel/build_unikernel.sh myserver.nu --fs ./image_root -o myserver.elf
unikernel/run_qemu.sh myserver.elf -t 60 -- \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:8443-:8443 \
    -device virtio-net-device,netdev=n0
```

Firecracker should take the same ELF as `--kernel-image` with `boot-args`
carrying the same keys — PVH is its boot protocol too, and the exit
sentinel exists because Firecracker has no channel for an exit code.
**Not gated, and therefore not claimed**: every measurement and every
gate in this directory is QEMU microvm. The plan has Firecracker as a
later step, and until a job boots one, treat the paragraph above as a
design intent rather than a tested path.

**The threat model, stated.** The hypervisor and whoever writes the
kernel command line are TRUSTED — they choose the image, its
certificate and its clock, so nothing here defends against them, and
`wallclock=` is a functionality input rather than a security control.
The NETWORK is not trusted: every byte that arrives from virtio-net is
parsed by `stdlib/net/`, which is fuzzed for exactly that
(`net_frame_fuzz`), and the driver clamps the lengths the DEVICE
reports because a device is on the other side of the same trust
boundary. There is no user/supervisor split inside the guest and no
attempt at one: a unikernel is one program in one address space, and a
privilege boundary with nothing on the other side of it is ceremony.

## An MCP endpoint that IS the machine

```
$ curl -X POST -d '{"jsonrpc":"2.0","id":3,"method":"tools/call",
                    "params":{"name":"echo","arguments":{"text":"from the host"}}}' \
       http://127.0.0.1:18992/mcp
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"from the host"}],
 "isError":false,"resultType":"complete"}}
```

The plan's endpoint milestone is a unikernel that boots straight into a
running MCP node. `unikernel/demos/mcpd.nu` is that shape: the dispatch
function and every layer under it are the repository's own echo server
(`examples/mcp_echo_server_http.nu`), unchanged — JSON-RPC over
Streamable HTTP, the same `mcp_http_handler` the corpus tests drive.
The only differences are the address it binds and the machine it binds
on.

The gate asks it three questions, because one would not tell "the
server answered" from "the server answered correctly": `initialize`
settles the protocol, `tools/list` settles the catalogue, and
`tools/call` settles that a tool ran and its output came back.

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

## Measured

`unikernel/bench_boot.sh` (QEMU 8.2, **TCG** — no `/dev/kvm` on this
machine):

| | |
|---|---|
| plaintext image | 363 128 bytes |
| TLS image | 387 176 bytes (the extra 24 KiB is the whole of TLS 1.3) |
| cold VM to first HTTP answer | 2.5 – 6.6 s |
| cold VM to first HTTPS answer | ~11 s |
| HTTP requests per second | 143 (100 sequential, one connection each) |
| heap after 200 requests | flat — growth 0 bytes after warm-up |

Two honest caveats, because the numbers are worth less without them.
TCG is an **interpreter**: it is the floor, not the ceiling, and the
plan's "low single-digit ms" target is a KVM number that this machine
cannot produce. And the spread on the plaintext figure is the
measurement's, not the guest's — the harness polls, so its resolution
is its retry interval plus QEMU's own start-up jitter. What the number
is good for today is noticing a regression; a real boot-time figure
needs the guest to timestamp its own first answer, which is the next
thing to add to it.

Everything above the "answer" is included: the hypervisor starting, the
guest booting, DHCP completing against QEMU's server, the socket
binding, and — for the TLS row — an RSA handshake, which is where most
of that eleven seconds goes on an interpreter.

The throughput row is **sequential**: one connection per request, so it
is latency's reciprocal rather than a concurrency figure, and calling it
anything else would flatter it. It comes from the same run as the heap
row — `demos/soak.nu`, the program the guest gate uses — because a
throughput number and a leak number measured on two different servers
are two numbers about two different programs.

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

All three gates run on every code change (the `unikernel` job):

| | |
|---|---|
| `run_nolibc_tests.sh` | the ordinary corpus, no libc linked — 451 programs against their existing goldens |
| `tests/run_unit_tests.sh` | the differentials against glibc, BOTH allocators fuzzed (the size-class one and the page allocator under it), the scheduler's schedule and its deadlock detector |
| `run_qemu_tests.sh` | the guest, 19 checks: boot, memory, TSC, fibers, the TCP/UDP stack, virtio-net, DHCP, a baked-in filesystem, two deliberate CPU faults and their reports, a 200-request soak with the heap watched, a 4 MiB machine and a 2 MiB one that refuses to boot, and three servers answering a client on the host — plaintext, MCP and TLS 1.3 |

The frame path has a gate of its own in the ordinary corpus:
`net_frame_fuzz` drives `stack_rx` with bytes nobody chose and asserts
what the layer above is entitled to believe — that a payload handed up
lies inside the frame it came from, that every drop is counted exactly
once, that every emitted frame is one a device could send, and that a
frame addressed to another machine is never answered. It is
mutation-validated against five injected parser bugs and runs in the
LSan leak gate.

The QEMU job runs under TCG because no runner has `/dev/kvm`. Slower,
identical otherwise — except for the TSC frequency, which no leaf
reports there, so `run_qemu.sh` states it on the kernel command line
the way the plan says the host states the epoch.

A gate that only exists on a developer's machine is a gate that
drifts; this repo has been bitten by that twice (the plan's findings 1
and 11), which is why these are jobs rather than instructions.

## Running the gates

```sh
unikernel/tests/run_unit_tests.sh        # strings / float format / libm /
                                         # both allocators / the scheduler
unikernel/run_nolibc_tests.sh            # the corpus, with no libc
unikernel/run_qemu_tests.sh              # the guest, under a hypervisor
unikernel/run_qemu_tests.sh hello        # one of them
unikernel/build_nolibc.sh prog.nu        # build one program, no libc
unikernel/build_unikernel.sh prog.nu     # build one bootable image
```

QEMU is the only thing the guest gate needs that a checkout does not
bring; without it the gate SKIPS with a message rather than failing, so
a developer without a hypervisor can still run everything else.

## What is deliberately missing

`nolibc` refuses rather than pretends. `opendir` returns NULL,
`isatty` answers 0, `tcgetattr` fails, `backtrace` finds no frames —
each is the honest answer for a target with no filesystem, no terminal
and no unwinder, and each makes the caller take its already-written
error path. None of them succeeds while doing nothing, which is how a
stub becomes someone else's bug report months later.
