// stdlib/std/sysinfo.nu — what machine is this, and how big?
//
// The three questions a program asks about its host that are not files
// and not the environment: the kernel and machine identity (`uname`),
// the host's name, and how many processors are online.
//
// Each of them is unportable in a different way — utsname is a struct
// whose field width is a kernel constant, the host name is a syscall on
// POSIX and a Win32 API elsewhere, and the processor count is a sysconf
// key — so the runtime answers and this module presents.
//
//   ( sys_uname_field SYS_SYSNAME )  → ?String   `Linux`
//   ( sys_hostname )                 → ?String   the node name
//   ( sys_cpu_count )                → i         online processors, >= 1
//
// A `None` means the platform genuinely cannot say (Windows has no
// utsname; a unikernel has no name to give), never a placeholder.
// Callers print what they got or fall back visibly — `uname -s` on a
// machine that will not say prints `unknown`, it does not print `Linux`.

$ `stdlib/core/string.nu`

& `c` @ nurl_uname_field i which → sink s

& `c` @ nurl_cpu_count → i

& `c` @ nurl_available_parallelism → i

: i SYS_SYSNAME 0
: i SYS_NODENAME 1
: i SYS_RELEASE 2
: i SYS_VERSION 3
: i SYS_MACHINE 4

// One utsname field as an owned String, or None where there is no
// utsname. `which` is one of the SYS_* constants above.
@ sys_uname_field i which → ?String {
    : s raw ( nurl_uname_field which )
    ? == # i raw 0 { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_adopt raw ) }
}

// The host's name — utsname's nodename, which is what `hostname` prints
// and what `uname -n` reports.
@ sys_hostname → ?String {
    ^ ( sys_uname_field SYS_NODENAME )
}

// Processors online. At least 1 on every target, including a machine
// that cannot count them, because a caller sizing a thread pool needs a
// number it can divide by.
@ sys_cpu_count → i {
    : i n ( nurl_cpu_count )
    ^ ? < n 1 1 n
}

// How many threads THIS PROCESS can run at once: the affinity mask
// (taskset / cpuset) capped by a container's cgroup CPU quota — what
// the fiber scheduler sizes its worker pool by when NURL_WORKERS is
// unset, and what Rust's available_parallelism() reports. sys_cpu_count
// is the machine's hardware count regardless of such limits.
@ sys_available_parallelism → i {
    : i n ( nurl_available_parallelism )
    ^ ? > n 0 n 1
}

// ── the operating system, and the host's memory ────────────────────
//
//   ( sys_os )              → i    one of SYS_OS_*: what this program was
//                                  compiled for (a link-time constant)
//   ( sys_mem_available )   → ?i   bytes the host can hand out now without
//                                  swapping
//   ( sys_mem_total )       → ?i   bytes of physical memory
//
// A host command line, a file suffix or a cache directory that differs by
// platform asks sys_os rather than reading $OS. Memory is None where the
// platform cannot say (wasm, the unikernel); "available" is Linux's
// MemAvailable, Windows' ullAvailPhys, and the free plus inactive pages on
// macOS and FreeBSD.

& `c` @ nurl_host_os → i

& `c` @ nurl_host_mem i which → i

: i SYS_OS_OTHER 0
: i SYS_OS_LINUX 1
: i SYS_OS_MACOS 2
: i SYS_OS_WINDOWS 3
: i SYS_OS_FREEBSD 4
: i SYS_OS_WASM 5
: i SYS_OS_UNIKERNEL 6

@ sys_os → i { ^ ( nurl_host_os ) }

@ sys_mem_available → ?i {
    : i n ( nurl_host_mem 0 )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T n }
}

@ sys_mem_total → ?i {
    : i n ( nurl_host_mem 1 )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T n }
}
