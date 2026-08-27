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
| `fs/`, `drivers/virtioblk.nu` | the disk: the `nurl_disk_*` shim the VFS calls, the two block-device spellings (a virtio device, or none), and the driver — one queue, three descriptors, a request at a time |
| `net/sockets.nu` | the socket ABI (`nurl_tcp_*`, `nurl_udp_*`, `nurl_dns_*`, `nurl_reactor_wait_*`) in NURL, over the sans-IO stack in `stdlib/net/` |
| `boot/` | the guest: PVH entry + long mode + SSE + the interrupt stubs (`boot.S`), the address space (`link.ld`), the machine's bottom edge (`platform_x86.c`), the pages themselves (`pagealloc.c`), the baked-in filesystem (`initfs.c`), the thread pointer without an auxv (`tls_guest.c`) — and their AArch64 counterparts `boot_arm64.S`, `link_arm64.ld`, `platform_arm64.c`, `tls_guest_arm64.c` (`pagealloc.c` and `initfs.c` are shared: portable C, one copy) |
| `drivers/` | `virtionet.nu` — frames in and out over a real device |
| `build_unikernel.sh` | build a `.nu` into a bootable PVH kernel image (x86_64) |
| `build_unikernel_arm64.sh` | the same, for AArch64 / QEMU `virt` |
| `run_qemu.sh` · `run_qemu_tests.sh` | boot one image · run corpus tests inside the guest against their goldens |
| `run_qemu_arm64.sh` · `run_qemu_arm64_tests.sh` | the AArch64 twins of those two |
| `compile_nu.sh` | compile one program, pulling in `net/sockets.nu` when (and only when) it calls the socket ABI |
| `demos/` | the programs that only make sense in the guest: devices, DHCP, a filesystem, a server, an MCP endpoint, TLS — and the two that are about failure, `fault.nu` and `soak.nu` |
| `k8s/` | the guest as an ordinary Kubernetes workload: an HTTP server, a container that carries a hypervisor and the image, and the manifests — unprivileged, no `/dev/kvm`, [its own README](k8s/README.md) |
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

## State (2026-08-27)

```
  PASS         516    corpus tests that build and run with no libc at all
  FAIL           0
  NEEDS-BARE    23    processes and signals — a unikernel has neither
  NEEDS-LIBM     0
  NEEDS-NOLIBC   5    inotify, execvp, unix sockets
  NEEDS-LIB      3    libsqlite3 — third-party C libraries
  SKIP         355    compile-fail tests and tests with no standalone build
```

`realpath` left that column when `packages/nurlbox` — a busybox-shaped
userland — was built for this target and found the holes: nolibc gained
`realpath`, `fdopen`, `link`/`symlink`/`readlink`, `chmod`, `getcwd`, the
uid/gid quartet, `getgroups`, `uname`, `sysconf` and `utimensat`, and the
guest's VFS gained `stat` and directory listing over the baked-in
archive. `ls -l`, `find`, `du` and `test -d` answer in the guest now.

The guest suite (`unikernel/run_qemu_tests.sh`) is **29/29**.

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
a serial port. No initrd, no bootloader and no kernel command line
beyond the keys below. A disk is OPTIONAL and always has been: without
one the only filesystem is the archive baked into the ELF, read-only,
and every write is refused rather than silently dropped. With one —
`-drive` plus `virtio-blk-device`, and an image built with `--disk` —
the same program's ordinary `write_file` / `read_file` / `dir_list`
calls reach a FAT volume any host can read.

**The kernel command line** is a contract, and every key is stated
rather than guessed:

| key | meaning | when it is required |
|---|---|---|
| `tsc_khz=N` | the TSC frequency | when no CPUID leaf reports one — i.e. under TCG. Asking for the time without it PANICS rather than inventing a number |
| `wallclock=N` | the boot epoch, seconds | whenever X.509 validity is checked: TLS client verification, and a server whose certificate has dates |
| `virtio_mmio.device=…` | where the devices are | appended by the hypervisor; the guest parses it, and a guest with no match reports "no device" rather than probing blindly |
| `args="…"` | the program's argv | when the program takes arguments. ONE key, quoted, because QEMU appends its own entries after `-append` and a program that read the tail of the line would be handed them |
| `ip=A.B.C.D/prefix` | the machine's own address | on a network with no DHCP server — a tap with static addresses, for instance. Told beats asked: with this key the guest does not run the DHCP client at all. Stated-but-unparseable exits 127 |
| `gw=A.B.C.D` | the default route | with `ip=`, when peers are off-subnet. Optional: a machine whose peers are all on its own subnet needs none, and an invented gateway is a first packet sent to a host that is not there |
| `dns=ip[:port]` | the resolver | when a name must resolve and DHCP's option 6 is absent or wrong; stated-but-unparseable exits 127 rather than resolving against a guessed server |
| `disk=rw\|ro\|format\|off` | what to do with the block device | only to say something other than `rw`. `ro` refuses every write with EROFS; `format` writes a filesystem **only onto a device that does not mount**, so it is not a reformat-on-every-boot switch; `off` makes the machine behave exactly as one with no disk. A guest with no virtio-blk device ignores the key |

Every other `key=value` token on the line is the guest's ENVIRONMENT:
`getenv("key")` answers it (boot/cmdenv.c; plan B7 always promised
this and the environment was left empty). `args="…"` stays argv's,
and a bare word is not an assignment.

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
| idle | `hlt`, woken by the local-APIC timer — TSC-deadline mode where the CPU has it, a TSC-calibrated one-shot where it does not (TCG). Devices stay POLLED (the B0 decision stands; the interrupt exists only to end a sleep, so deadlock stays decidable), and the poller's cadence backs off 1 → 16 ms when no traffic moves — the first frame after a quiet spell waits at most 16 ms. Measured on an idle joined worker appliance under TCG: a full host core before, 5.6 % after. `demos/idle.nu` gates that the machine really halts |
| memory | whatever the hypervisor reports; 256 MiB is what the gates run with, 4 MiB is what a server needs (see above) |
| MTU | 1500. Frames are refused above 2036 bytes rather than truncated |
| IP fragments | dropped, counted, never reassembled. A datagram over the MTU does not arrive — and the direct leg no longer needs one to: `net/securedgram` chunks its messages under the MTU itself (reassembled above the AEAD), which is what lifted plan B10's "worker pins relay mode" restriction. Chunking removes the MTU limit, not packet loss: with no ARQ one lost chunk loses the message, so the direct leg caps a message at 256 KiB and `net/transport` routes anything larger over the relay leg, where TCP owns segmentation and retransmission |
| storage | a virtio-blk disk, FAT12/16/32, read AND write — long names, subdirectories, rename, truncate, `readdir`, `fsync`. Opt-in at build time (`--disk`), measured at **+72 KiB** of image over the same program without it. The guest can `mkfs` a blank disk itself (`disk=format`); the volume it makes and the volumes it writes are both called clean by `fsck.vfat`. **No journal**: `fsync` orders data and its FAT chain before the directory entry, so a crash loses the newest bytes rather than the file, but a crash between two writes can still leave clusters no directory names — which `fsck.vfat` reclaims. Sectors are 512 bytes and a volume that says otherwise is refused at mount rather than read at the wrong offsets |
| open files | 16 from the baked-in archive (read-only) plus 32 on the disk. A path the IMAGE holds is served from the image even when the disk has the same name — the archive is part of the program, and a guest whose behaviour depended on what an attached disk happened to contain would be one nobody can reason about |
| stat on a disk file | `stat`/`lstat`/`fstat` still answer -ENOSYS, so `path_type` does not see the disk. `open`, `lseek`, `access` and `readdir` (with `d_type`) do, which is what `file_exists`, `file_size`, `read_file` and `dir_list` are built on |
| TCP | immediate ACKs, no Nagle, fixed 64 KB window (the peer's window scaling is honored), slow start + fast retransmit; **no SACK, no delayed ACK, no cwnd beyond slow start** — and that list is now MEASURED as a non-limit, not assumed: a 4 MiB bulk transfer over virtio moves 1.56 MiB/s under TCG with the guest CPU at 93 % of a core — the interpreter is the ceiling, while the 64 KB window at sub-millisecond RTT allows two orders of magnitude more. SACK pays only on lossy paths, which neither virtio nor this gate's topology has; it returns when a real deployment on one measures a need |
| sockets | 1024 open at once (`sock_set_max_fds` to change it); past that `accept` refuses and leaves the connection in the backlog rather than the machine running out. Ephemeral ports are per-protocol; TCP and UDP have separate spaces |
| name resolution | literals, `localhost`, and A records from the resolver the network announced — DHCP option 6, or a `dns=ip[:port]` cmdline key (the same host-states-a-fact contract as `wallclock=`; unparseable = exit 127). The query rides `stdlib/net/dnsclient.nu` over the pure UDP stack: stub-resolver scope, so a TC-bit answer is an error (no TCP retry), CNAMEs are followed only inside the one response, and hostile compression pointers run out of hop budget rather than time. No resolver → a name is refused, not guessed |
| processes, signals | none. `fork`/`exec` report unsupported; there is one address space and nothing to fork |
| vCPUs, again | one, and every layer above assumes it: the block driver waits for its own request rather than queueing, the scheduler is cooperative, and the allocator takes no lock. SMP is not a missing flag — it is a different set of invariants |
| GPU | none in a microVM; a swarm node advertises CPU-wasm capability only |

**Building and running one:**

```sh
unikernel/build_unikernel.sh myserver.nu --fs ./image_root -o myserver.elf
unikernel/run_qemu.sh myserver.elf -t 60 -- \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:8443-:8443 \
    -device virtio-net-device,netdev=n0
```

**With a disk**, which is a different image (`--disk` links the block
layer in) and two more QEMU arguments:

```sh
truncate -s 64M state.img && mkfs.vfat -F 32 state.img   # or: boot once with disk=format
unikernel/build_unikernel.sh myserver.nu --disk -o myserver.elf
unikernel/run_qemu.sh myserver.elf -t 60 -- \
    -drive file=state.img,format=raw,if=none,id=d0 \
    -device virtio-blk-device,drive=d0
```

Afterwards `fsck.vfat state.img` checks it and anything that reads FAT
can open it — which is why the format is FAT and not something of our
own: an appliance whose state only its own author can inspect is an
appliance nobody should run.

Firecracker takes the same ELF as `--kernel-image` with `boot-args`
carrying the same keys — PVH is its boot protocol too, and the exit
sentinel exists because Firecracker has no channel for an exit code.
How much of that is gated is stated in the hypervisor section below:
the PVH note's structure always, a real cloud-hypervisor/Firecracker
boot wherever `/dev/kvm` is usable (CI's runner is), and **every
MEASUREMENT in this file is QEMU microvm** — the other two boot the
image, but no throughput or boot-time figure is claimed for them.

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

## A disk, and state that outlives the machine

```
$ truncate -s 32M state.img && mkfs.vfat -F 16 state.img
$ unikernel/build_unikernel.sh --disk unikernel/demos/disk.nu -o disk.elf
$ unikernel/run_qemu.sh disk.elf -t 60 -- \
      -drive file=state.img,format=raw,if=none,id=d0 -device virtio-blk-device,drive=d0
boots_before=0
...
$ unikernel/run_qemu.sh disk.elf -t 60 -- ...same...
boots_before=1
$ python3 unikernel/tests/fatread.py state.img /boots.txt
/boots.txt=2
```

Until this existed the only filesystem was the tar inside the ELF, and
every write was a refusal — which is correct for a machine with nowhere
to put the bytes and fatal for anything that has to remember something.
A database, a write-ahead log, a cache, a queue: all of them need the
same four things, and none of them could run here.

**The stack, bottom to top.** `drivers/virtioblk.nu` is the device: one
queue, three descriptors per request (a header the driver writes, the
data, one status byte the device writes), and each request waited for
rather than queued — a cooperative scheduler on one vCPU has nothing to
do with queue depth, and a completion running while a filesystem is
halfway through a directory is a bug class rather than a feature.
`stdlib/hal/blockdev.nu` is the seam: four `nurl_blk_*` symbols,
declared there and answered by a virtio device, by nothing, or by a
file on a host — which is how the layers above are developed and
fuzzed where `mkfs.vfat` is. `stdlib/fs/fat.nu` and `fatfs.nu` are the
filesystem, and `boot/vfs.c` is what makes it invisible: `nl_open`,
`read`, `write`, `lseek`, `unlink`, `rename`, `mkdir`, `truncate`,
`fsync`, `access` and `getdents64` ask the baked-in archive first and
the disk second, so a program that already reads and writes files keeps
working with nothing added to it. `demos/disk.nu` contains no
disk-aware call at all.

**Why FAT.** Because the alternative is a format only its own author can
read. `mkfs.vfat` builds the volumes the gate tests against, `fsck.vfat`
delivers the verdict on what the guest wrote, and
`unikernel/tests/fatread.py` — a reader in another language that shares
no code with this one — checks that the bytes are where the directory
says they are, which is a different question from "is the structure
consistent" and the one a cluster-arithmetic bug gets wrong. An
implementation that can only be checked by itself is one whose bugs
surface after somebody's data is already in it.

**What it does not have is a journal**, and it does not pretend
otherwise. `fsync` puts data and the FAT chain that names it on the
medium before the directory entry that publishes the new size, so a
crash loses the newest bytes rather than the file that held them — but
a crash between two of those writes can still leave clusters no
directory names. That is lost space, `fsck.vfat` reclaims it, and it is
written down here rather than discovered later.

**Three bugs this cost**, each invisible to the layer that had it:

- **The formatter's FAT size did not converge.** Sizing a FAT is a
  recurrence — a bigger table leaves fewer data sectors, which need
  fewer entries — and on a 64 MiB disk it OSCILLATES between 1008 and
  1009 sectors for ever. A loop looking for a fixed point ran out of
  iterations and returned whichever it stopped on; when that was the
  smaller one, the table was one entry short of the clusters the volume
  claimed. The criterion is safety, not equality: grow until the table
  covers the clusters, then shrink while it still does.
- **The disk layer was compiled and then dropped.** Nothing in NURL
  calls `nurl_disk_open` — `boot/vfs.c` does — so dead-code elimination
  removed the whole filesystem, the image linked (the C side's
  references are weak on purpose), booted, and reported "no filesystem"
  about a filesystem it was carrying. A function reachable only from
  outside the module has to be named from outside it: `nurlc --keep=`.
- **`mmap` of a disk file returned anonymous pages.** `read_file` maps
  rather than reads, the guest's `mmap` answered file-backed requests
  with a pointer into the baked-in image, and a disk file has no such
  address — so a file the guest had just written came back as "cannot
  read". A private read-only mapping is a snapshot, and a snapshot may
  be a copy.

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

## The endpoint milestone: a swarm compute appliance

The plan's acceptance test (B10) was a unikernel that boots straight
into a running **swarm-mcp** node, and `unikernel/tests/swarm_gate.sh`
now runs it on every commit. The SAME `packages/swarm-mcp` source
builds both ways: hosted (a relay and the MCP control surface on the
host) and as a guest image. The guest boots, `--connect`s OUT through
the pure TCP stack and virtio-net, appears in `swarm_census`, and
completes both kernel flavours end-to-end — an expression task
(sum of x² over [0,1000) = 332833500) and a **compiled-wasm task**:
the coordinator compiles the NURL kernel to wasm32-wasi on the host
and the guest executes the chunks **in-process on the pure-NURL
`nwasm` runtime**, because a machine with no processes cannot shell out
to a runtime and now does not need to.

Measured on this gate (TCG, an interpreter floor): census join 6 s
after launch, cold start to the first completed tool answer 9 s. A
guest advertises CPU-wasm capability only; a GPU request answers
exactly like a hosted machine with no NVIDIA driver, because the
image links the same `cuda_stubs.c` that nurl.sh uses there.

## The compiler, as wasm, inside the machine

```
$ unikernel/tests/wasmc_gate.sh
wasmc_gate: nurlc.wasm: 1540481 bytes
wasmc_gate:   hello.nu: byte-identical to native (6624 bytes)
…
wasmc_gate: verified: 8 programs compiled by nurlc.wasm IN THE GUEST,
            byte-identical to native (23s)
```

`compiler/nurlc.nu` compiled to wasm32-wasi (by `packages/wasmbuilder`,
locally — native nurlc for the IR, zig's wasm-ld for the link) is baked
into an image beside a handful of corpus programs and the IR the NATIVE
compiler produced for them. The guest decodes the module on
`packages/nwasm` and runs it IN-PROCESS, because a machine with no
processes has no other way to run it, and compares its output BYTE FOR
BYTE with the native compiler's. All eight agree.

`unikernel/tests/selfhost_gate.sh` puts `compiler/nurlc.nu` itself in
that image — it has no imports either, so it costs one more file — and
then the comparison is the bootstrap fixed point: the guest re-emits
the 4 337 947 bytes `nurlc.wasm` was linked from, which is the equality
`build.sh` checks between `nurlc_self.ll` and `nurlc_self2.ll`, with
the compiler running as wasm and nothing underneath it. It is a
separate script and run by hand, because the guest spends 22 minutes on
it under TCG against 23 s for the eight above.

That comparison is the claim worth making. "The wasm build works" is
about a pipeline; "the compiler emits the same bytes with no libc, no
kernel and no host underneath it" is about the language. Two defects
had to be fixed before it was true, and neither was visible anywhere
else:

- `nurl_sym_free` walked the symbol table's pointer arrays as `*i`
  while every other reader and the writer use `*s`. On a 64-bit target
  those spellings address the same bytes; on wasm32 a pointer is four,
  so each read fused two entries into one bogus address and `free`
  read a chunk header outside linear memory. nurlc.wasm trapped after
  emitting correct IR.
- the initfs ignored `O_DIRECTORY`, so `opendir` SUCCEEDED on a regular
  file. Every "is this a directory?" predicate written the obvious way
  then says yes about a file — including the wasm runtime's
  `path_open`, which handed the compiler an empty directory fd and got
  a compile of an empty program, with no error anywhere.

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
