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
| `boot/` | the guest: PVH entry + long mode + SSE + the interrupt stubs (`boot.S`), the address space (`link.ld`), the machine's bottom edge (`platform_x86.c`), the pages themselves (`pagealloc.c`), the baked-in filesystem (`initfs.c`), the thread pointer without an auxv (`tls_guest.c`) — and their AArch64 counterparts `boot_arm64.S`, `link_arm64.ld`, `platform_arm64.c`, `tls_guest_arm64.c` (`pagealloc.c` and `initfs.c` are shared: portable C, one copy) |
| `drivers/` | `virtionet.nu` — frames in and out over a real device |
| `build_unikernel.sh` | build a `.nu` into a bootable PVH kernel image (x86_64) |
| `build_unikernel_arm64.sh` | the same, for AArch64 / QEMU `virt` |
| `run_qemu.sh` · `run_qemu_tests.sh` | boot one image · run corpus tests inside the guest against their goldens |
| `run_qemu_arm64.sh` · `run_qemu_arm64_tests.sh` | the AArch64 twins of those two |
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
| sockets | 1024 open at once (`sock_set_max_fds` to change it); past that `accept` refuses and leaves the connection in the backlog rather than the machine running out. Ephemeral ports are per-protocol; TCP and UDP have separate spaces |
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

## Which hypervisors, and what the artifact actually is

The image is an ELF with a `XEN_ELFNOTE_PHYS32_ENTRY` note in it. That
note is the whole PVH direct-boot protocol: a loader reads the address
out of it and jumps there, in 32-bit protected mode, with the handover
block in `%ebx`. **QEMU, Firecracker and cloud-hypervisor all do
exactly that**, so the same file boots on all three with no
repackaging — Firecracker documents PVH as the mode it picks when the
note is present, and it is what FreeBSD boots there with.

`unikernel/tests/hypervisor_gate.sh` is the check, and it has two
halves because they answer different questions. The STRUCTURE half
runs anywhere: the note exists, is owned by `Xen`, is type 18, carries
a four-byte descriptor, and the address in it **equals the ELF's own
entry point** — those last two are set by different files (`boot.S`
and `link.ld`) and a mismatch is a boot that works under one loader
and not another. The BOOT half runs cloud-hypervisor and Firecracker
for real; both require `/dev/kvm` and neither has an interpreter
fallback, so on a machine without it the gate says so and skips rather
than passing quietly. Three deliberate mutations — the entry point
moved, the note's type changed, the section renamed away — are all
caught by the structure half.

On AArch64 the container differs and the build now produces both.
PVH is x86-only; what Firecracker and cloud-hypervisor take there is a
flat **`Image`** — the format a Linux arm64 kernel ships in — so
`boot_arm64.S` puts that format's 64-byte header at offset 0 of the
same build and `build_unikernel_arm64.sh` emits `prog.Image` beside
`prog.elf`. One program, two wrappers: `code0` is a branch over the
header, so a loader that jumps to offset 0 and an ELF loader that
jumps to the entry point arrive at the same instruction. `text_offset`
is 2 MiB because this image is **not** position-independent — the
field is what makes a loader place it where its absolute addresses
already point — and `image_size` covers `.bss`, so the loader reserves
what the program grows into rather than what the file holds.

The gate checks the header the same way it checks the PVH note (magic,
`code0` really a branch, `text_offset` equal to where the image is
linked inside its region, `image_size` ≥ the file), and four
mutations — magic cleared, `code0` zeroed, offset zeroed, size shrunk
— are all caught. Booting Firecracker or cloud-hypervisor on this
container needs an **AArch64 host**: neither emulates, so there is
nothing on an x86 developer machine to run them on, and the gate says
that rather than implying coverage it does not have. QEMU boots the
flat Image here, which is what proves the header's branch and its load
address agree.

## On real hardware, off a USB stick

None of the above helps on a PC. A PVH note is a thing hypervisors
read; a BIOS reads a 512-byte boot sector and a UEFI firmware reads a
PE executable off a FAT partition, and neither has ever heard of it. So
`boot/boot.S` carries a **Multiboot2 header** beside the PVH note and
has a second entry point, `_mb2_start`, for the loader that reads it.

The two entries meet six instructions later. PVH and Multiboot2 hand
over in the same machine state — 32-bit protected mode, paging off,
interrupts off, a flat GDT, the handover block in `%ebx` — so
everything from the page tables onwards is shared. What differs is the
shape of that block, and `boot/multiboot2.c` converts one into the
other: it walks the tag stream once and writes an `hvm_start_info`
with a flat memory-map array behind it, so `kmain` and `mem_init`
never learn there was more than one way in. The memory records agree
field for field and both use E820's numbering, which is what makes the
conversion a copy rather than a translation.

    unikernel/build_unikernel.sh        prog.nu -o prog.elf
    unikernel/build_bootable_image.sh   prog.elf -o prog.img
    sudo dd if=prog.img of=/dev/sdX bs=4M conv=fsync status=progress

`prog.img` is a hybrid: an El Torito ISO that is also a valid MBR/GPT
disk with a FAT EFI system partition inside it. One `dd` serves both
firmwares. The kernel and the GRUB config are embedded in each boot
image's **memdisk** rather than read off the filesystem, which takes
iso9660, FAT and the partition-table drivers out of the boot path
entirely — by the time GRUB runs `multiboot2`, everything it needs is
already in memory.

`grub-mkrescue` is the obvious tool and is not used. Its `-d` takes one
platform directory and derives nothing, so pointed at a module tree
outside `/usr/lib/grub` it builds for one firmware and silently omits
the other. That would make "the UEFI half is missing" the normal
consequence of not having root, and the symptom is a machine that sits
there, on someone else's desk. The two boot images are built separately
with `grub-mkstandalone` and assembled with `xorriso` instead, both of
which take an explicit module directory — so the build runs
unprivileged, in CI and in a container.

### What a PC has that a microvm does not, and the reverse

**No serial port.** A laptop has no 8250 at `0x3F8`, so a guest that
prints only there is indistinguishable from one that never started.
`boot/console.c` draws the same bytes on the screen: EGA text at `0xB8000`
under a BIOS, and a linear framebuffer with the 8x16 font in
`boot/font8x16.c` under UEFI, which has no text memory at all. Only
white on black is drawn, which is why no pixel-format masks are needed
— white is all bits set in every RGB layout there is. The console is
armed **only** on a Multiboot2 boot, so the hypervisor path keeps
exactly the output its 20/20 gate is written against.

That console is also why the Multiboot2 header requests a framebuffer
and why `build_bootable_image.sh` writes `insmod all_video` into its
GRUB config. Having the module in the image is not the same as having
loaded it, nothing loads a video driver on demand, and without that one
line a UEFI boot reports `no suitable video mode found`, hands over no
framebuffer, and runs perfectly with a blank screen.

**Nobody states the TSC frequency.** There is no hypervisor to ask, and
on an AMD part neither CPUID leaf 0x15 nor 0x16 exists — so a machine
booted off iron would panic the first time anything asked what time it
was. A PC does have a 1.193182 MHz oscillator that has not changed
since 1981, so `pit_calibrate_khz` counts TSC ticks against PIT channel
2 for 10 ms. Measured, not guessed, which is the only thing this
directory will do with a clock; `nurl_clock_source` reports which of
the five sources answered, because a clock is exactly as trustworthy as
whatever told you its rate.

**The bootloader re-quotes the command line.** QEMU passes `-append`
through untouched, so the guest sees `args="alpha beta"`. GRUB's parser
consumes the quotes while tokenising and puts them back around the
whole token, so the guest sees `"args=alpha beta"` — the same
information, one quote earlier. Matching the literal six characters
`args="` finds the first spelling and silently misses the second, which
is a program that gets no arguments and no explanation. `build_argv`
now finds the key and lets the quoting decide where the value ends.

`demos/baremetal.nu` is the program to put on the stick first. It
prints what the machine says about itself — console, CPU brand, RAM,
clock and its provenance, command line, argv — runs four checks that
verify rather than print (a vector past its first allocation, 400 bytes
of string, `sqrt(2)` squared, a fold), and then beats once a second for
ever. It never exits: on iron there is nothing to exit to, and
returning from `main` switches the computer off in front of whoever
just plugged the stick in.

`unikernel/tests/baremetal_gate.sh` is the check, in three levels that
each degrade to a loud skip. HEADER runs anywhere: the magic is 8-byte
aligned within the first 32 KiB of the **file** (which is what a loader
scans), the checksum sums to zero, the entry tag points at
`_mb2_start` and not at `_pvh_start`, the framebuffer tag is there.
IMAGE packages the hybrid disk and confirms El Torito records for both
firmwares. BOOT runs it under SeaBIOS and waits for the guest's own
exit line. Three mutations — the entry tag moved to `_pvh_start`, the
framebuffer tag deleted, the checksum broken — are all caught, and two
of them break a real boot as well.

## Three architectures, and what a port actually costs

| | x86_64 | AArch64 | RV64 |
|---|---|---|---|
| board | QEMU microvm (PVH) | QEMU `virt` | QEMU `virt` + OpenSBI |
| entry | 32-bit, `%ebx` = handover | EL2 or EL1, `x0` = DTB | S-mode, `a1` = DTB |
| memory from | PVH memmap | device tree | device tree |
| devices from | kernel command line | device tree | device tree |
| clock | TSC, frequency **told** | CNTFRQ_EL0 | `rdtime`, tree's rate |
| entropy | RDRAND | RNDR | **virtio-rng** (no instruction exists) |
| hello image | 132 760 B (ELF) | 131 784 B (ELF) · 102 632 B (Image) | 155 344 B (ELF) |

The per-architecture files are the bottom edge and nothing else:
`boot_<arch>.S`, `platform_<arch>.c`, `tls_guest_<arch>.c`,
`nolibc/setjmp_<arch>.S`, `link_<arch>.ld`. Everything above them —
the runtime, nolibc, the sans-IO TCP/IP stack, the socket ABI, the
virtio driver, the program — is the same code, which each guest gate
proves by running the ordinary corpus against its ORDINARY hosted
goldens.

Two things became shared rather than copied when the third port
arrived, which is the right time for it:

- **`boot/fdt.c`** — the device-tree walk. AArch64 and RV64 need the
  same three answers (where RAM is, what the command line says, which
  virtio-mmio devices exist) out of the same format, and two ports
  parsing one tree separately is where two machines start disagreeing
  about what it says. It also does the translation that keeps the
  layer above architecture-blind: `hal/virtio.nu` reads the x86
  spelling `virtio_mmio.device=size@base:irq`, so the walker
  SYNTHESIZES those entries from the tree.
- **`boot/pagealloc.c`** and **`boot/initfs.c`** were already portable
  C and are linked by all three unchanged.

### RV64 (QEMU `virt`), the third one

OpenSBI runs first and hands the kernel S-mode with `a0` = hart id and
`a1` = the device tree, so this port does less at entry than either
twin: no mode change, no page tables before C. What it does do is park
every hart but one (this runtime is a single vCPU by design), set
`stvec` before anything can trap, turn FP on (`sstatus.FS` comes up
Off, and LLVM emits FP for ordinary doubles), and switch the trap
handler to its own stack by hand — this architecture has no automatic
stack switch on trap, which AArch64 gets free from SP_EL1 and x86 from
the TSS's IST.

Three things this port had to say out loud rather than assume:

- **`fp` IS `s0`.** The device-tree pointer was parked in `s0` and
  three instructions later `li fp, 0` ended the frame-pointer chain —
  zeroing it. The guest then reported "no device tree in a1", which
  was a true statement about a register this file had just cleared.
  An assembly probe of the firmware handover is what told them apart.
- **The firmware talks.** OpenSBI prints a banner on the same UART
  before the kernel runs, so the guest marks its own first byte
  (`[nurl-boot]`) and the run script drops everything up to it. The
  rule belongs to us rather than to whatever the banner looks like
  this year.
- **There is no entropy INSTRUCTION**, so the answer comes from a
  device. RISC-V's `seed` CSR is the optional Zkr extension and QEMU's
  rv64 CPU does not implement it, so `boot/virtio_rng.c` drives a
  virtio-rng device instead — the same layer the other two answer
  from, a different source. A machine started without `-device
  virtio-rng-device` is told so BY NAME: the rule stays absolute, no
  source is a panic and never a fallback, because "your TLS handshake
  failed" is a much worse way to learn it. With the device, **TLS 1.3
  works on this architecture** — an RSA-2048 handshake against the
  guest completes in 84 s under TCG, which is the interpreter's price
  rather than the protocol's.

  The driver is C in the boot layer and deliberately not
  `stdlib/hal/virtq.nu`: `getrandom` is a libc-level call that must
  work with no NURL module linked, for a program that never touches
  the socket layer. One queue, one buffer, no negotiation beyond the
  version bit — the same protocol as the network driver at a different
  layer, not a second implementation of it. It trusts the device for
  BYTES and not for the count: a device claiming to have written more
  than the buffer holds is refused rather than believed.

  The gate checks both halves, because a fake source passes the
  obvious one: with the device, a draw must be neither all zeroes nor
  equal to the next draw; without it, the machine must refuse by name.

`unikernel/run_qemu_riscv64_tests.sh` is the gate — **15/15**, the
same corpus programs against the same hosted goldens, the device
demos, faults reported with exit 126, and an HTTP server in the guest
answering curl on the host. The hello image is 155 344 B, about 23 KB
more than the other two: this ISA needs more instructions to say the
same things, which is the honest reading of the number rather than
something to tune away.

## The second architecture (AArch64, QEMU `virt`)

A second machine is what turns "portable" from an intention into a
measured property, and the port is the size the design predicted:
**four files** differ, and they are the four that talk to the machine.

| | |
|---|---|
| `boot/boot_arm64.S` | EL2→EL1, FP/SIMD un-trapped, the vector table, `.bss`, the two stacks |
| `boot/platform_arm64.c` | PL011 UART, the device tree, the MMU, the generic timer, RNDR, PSCI shutdown |
| `boot/tls_guest_arm64.c` | the thread pointer — variant I, and **measured**, not assumed |
| `nolibc/setjmp_aarch64.S` | `panic`/`recover`'s callee-saved set (which here includes `d8`–`d15`) |

Everything else is the same code the x86_64 image runs: the runtime,
nolibc, the sans-IO TCP/IP stack, the socket ABI, the virtio driver,
the NURL program. `stdlib/runtime_ctx.c` gained an AArch64 fiber
switch (AAPCS64: `x19`–`x28`, `x29`/`x30`, `d8`–`d15` and FPCR) beside
the x86 one; the two are read together.

The gate is `unikernel/run_qemu_arm64_tests.sh` — **15/15**: the same
corpus programs against the same hosted goldens, the device demos,
faults reported with exit 126, and an HTTP server in the guest
answering `curl` on the host. A hello image is **131 784 bytes**, which
is within a kilobyte of the x86_64 one (132 760) — the same program,
the same runtime, two instruction sets. The floor is **5 MiB** (4 fails
with `no usable memory above the image`: `virt` starts RAM at 1 GiB and
the image links 2 MiB in).

Three differences worth stating, because each was a debugging round:

- **The device tree replaces the command line.** microvm announces its
  virtio-mmio devices on the kernel command line; `virt` announces them
  in the DTB. `platform_arm64.c` parses the tree and SYNTHESIZES the
  same `virtio_mmio.device=size@base:irq` entries, so the NURL layer
  above sees one format on both machines. `/chosen/bootargs` becomes
  the command line the same way.
- **`virt` is legacy virtio-mmio by default**, exactly as microvm is —
  the guest read `version=1` off the register and refused every device,
  correctly. `-global virtio-mmio.force-legacy=false` is as necessary
  here as there.
- **The clock is self-describing.** `CNTFRQ_EL0` states the frequency,
  so there is no `tsc_khz=` handshake — that flag is an x86 quirk, not
  part of the contract. `wallclock=` stays: a wall clock is the host's
  to state on any machine.

And one thing that is deliberately not assumed: the TLS image's offset
from the thread pointer depends on the PT_TLS alignment the LINKER
chose. `tls_guest_arm64.c` places the image, reads a canary
`__thread` variable back through the compiler's own addressing, and
accepts the placement only when the value is there — otherwise it says
so and stops. A thread-local block that is off by sixteen bytes reads
plausible garbage, which is the worst way for a port to be wrong.

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
unikernel/run_qemu_arm64_tests.sh        # the guest, on the other architecture
unikernel/run_qemu_riscv64_tests.sh      # …and on the third
unikernel/tests/hypervisor_gate.sh       # the image is not a QEMU image
unikernel/build_nolibc.sh prog.nu        # build one program, no libc
unikernel/build_unikernel.sh prog.nu     # build one bootable image (x86_64)
unikernel/build_unikernel_arm64.sh p.nu  # …and for AArch64 (needs zig)
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
