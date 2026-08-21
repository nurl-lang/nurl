/*
 * NURL nolibc — unikernel/nolibc/syscall_linux.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The one file that talks to a kernel. Everything else in nolibc/ is
 * portable C that calls these six wrappers, so the unikernel target
 * replaces THIS file (writes to a UART, reads from a baked-in image)
 * and keeps the rest byte-for-byte.
 *
 * Linux/x86_64 calling convention: number in rax, arguments in
 * rdi/rsi/rdx/r10/r8/r9, `syscall`, result in rax, and rcx/r11 are
 * clobbered by the instruction itself. A negative result in
 * [-4095, -1] is -errno; the wrappers below hand that split to callers
 * rather than inventing a second convention.
 */
#include "nolibc.h"

long nl_syscall6(long n, long a, long b, long c, long d, long e, long f) {
    long ret;
    register long r10 __asm__("r10") = d;
    register long r8  __asm__("r8")  = e;
    register long r9  __asm__("r9")  = f;
    __asm__ volatile ("syscall"
                      : "=a"(ret)
                      : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9)
                      : "rcx", "r11", "memory");
    return ret;
}

/* Syscall numbers, x86_64. Spelled out rather than included from
 * <sys/syscall.h> so this file compiles with no system headers. */
#define SYS_read        0
#define SYS_write       1
#define SYS_open        2
#define SYS_close       3
#define SYS_lseek       8
#define SYS_mmap        9
#define SYS_munmap     11
#define SYS_exit_group 231

#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define MAP_PRIVATE   0x02
#define MAP_ANONYMOUS 0x20

int nl_errno_slot;
int *__errno_location(void) { return &nl_errno_slot; }

/* -errno in, -1 out with errno set — the libc convention the runtime
 * expects from read/write/open. */
long nl_ret(long r) {
    if (r < 0 && r > -4096) { nl_errno_slot = (int)-r; return -1; }
    return r;
}

nl_ssize_t nl_write(int fd, const void *buf, nl_size_t n) {
    return nl_ret(nl_syscall6(SYS_write, fd, (long)buf, (long)n, 0, 0, 0));
}
nl_ssize_t nl_read(int fd, void *buf, nl_size_t n) {
    return nl_ret(nl_syscall6(SYS_read, fd, (long)buf, (long)n, 0, 0, 0));
}
int nl_open(const char *path, int flags, int mode) {
    return (int)nl_ret(nl_syscall6(SYS_open, (long)path, flags, mode, 0, 0, 0));
}
int nl_close(int fd) {
    return (int)nl_ret(nl_syscall6(SYS_close, fd, 0, 0, 0, 0, 0));
}
nl_off_t nl_lseek(int fd, nl_off_t off, int whence) {
    return nl_ret(nl_syscall6(SYS_lseek, fd, off, whence, 0, 0, 0));
}
void *nl_map(nl_size_t len) {
    long r = nl_syscall6(SYS_mmap, 0, (long)len, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (r < 0 && r > -4096) return 0;
    return (void *)r;
}
int nl_unmap(void *p, nl_size_t len) {
    return (int)nl_ret(nl_syscall6(SYS_munmap, (long)p, (long)len, 0, 0, 0, 0));
}
void nl_exit_group(int code) {
    nl_syscall6(SYS_exit_group, code, 0, 0, 0, 0, 0);
    for (;;) { }                       /* unreachable; keeps `noreturn` true */
}

/* ── the libc-named wrappers ────────────────────────────────────
 * Everything above is internal (nl_*); everything below carries the
 * name the compiler emits, because NURL's `& `libc` @ …` declarations
 * call these directly. They are one syscall each — no libc logic, no
 * buffering, no errno translation beyond the -errno split above — so
 * the unikernel replaces them with device work and keeps every caller.
 *
 * The list is measured: it is what the corpus asked for when run under
 * nolibc, minus the ones that need more than a syscall (execvp's PATH
 * search, realpath, mkstemp, sigaction's restorer trampoline), which
 * are their own work rather than a line here.
 */
#define SYS_open_       2
#define SYS_stat_       4
#define SYS_poll_       7
#define SYS_madvise_   28
#define SYS_dup2_      33
#define SYS_pipe_      22
#define SYS_getpid_    39
#define SYS_fork_      57
#define SYS_wait4_     61
#define SYS_fcntl_     72
#define SYS_ioctl_     16
#define SYS_access_    21
#define SYS_nanosleep_ 35
#define SYS_rename_    82
#define SYS_mkdir_     83
#define SYS_rmdir_     84
#define SYS_unlink_    87
#define SYS_chdir_     80
#define SYS_chmod_     90
#define SYS_exit_      60
#define SYS_clock_gettime_ 228
#define SYS_mprotect_  10
#define SYS_getrandom_ 318
#define SYS_fsync_     74
#define SYS_truncate_  76
#define SYS_pread64_   17
#define SYS_pwrite64_  18

/* Positional read/write. `stdlib/runtime_core.c` calls these through its
 * `nurl_pread`/`nurl_pwrite` shims, so nolibc has to have them — that is
 * what `tools/check_nolibc_symbols.sh` asserts, and it caught their
 * absence in the PR that introduced the caller rather than at link time
 * months later. */
long long pread(int fd, void *buf, unsigned long n, long long off) {
    return nl_ret(nl_syscall6(SYS_pread64_, fd, (long)buf, (long)n, (long)off, 0, 0));
}
long long pwrite(int fd, const void *buf, unsigned long n, long long off) {
    return nl_ret(nl_syscall6(SYS_pwrite64_, fd, (long)buf, (long)n, (long)off, 0, 0));
}
long long read(int fd, void *buf, unsigned long n)  { return nl_read(fd, buf, n); }
long long write(int fd, const void *buf, unsigned long n) { return nl_write(fd, buf, n); }
int   close(int fd)                                 { return nl_close(fd); }
int   open(const char *p, int fl, int mode)         { return nl_open(p, fl, mode); }
long long lseek(int fd, long long off, int whence)  { return nl_lseek(fd, off, whence); }
int   munmap(void *p, unsigned long len)            { return nl_unmap(p, len); }
void *mmap(void *addr, unsigned long len, int prot, int flags, int fd, long off) {
    long r = nl_syscall6(SYS_mmap, (long)addr, (long)len, prot, flags, fd, off);
    if (r < 0 && r > -4096) { nl_errno_slot = (int)-r; return (void *)-1; }
    return (void *)r;
}
int   getpid(void)                                  { return (int)nl_ret(nl_syscall6(SYS_getpid_,0,0,0,0,0,0)); }
int   fork(void)                                    { return (int)nl_ret(nl_syscall6(SYS_fork_,0,0,0,0,0,0)); }
int   waitpid(int pid, int *status, int opts)       { return (int)nl_ret(nl_syscall6(SYS_wait4_, pid, (long)status, opts, 0, 0, 0)); }
int   pipe(int fds[2])                              { return (int)nl_ret(nl_syscall6(SYS_pipe_, (long)fds, 0, 0, 0, 0, 0)); }
int   dup2(int a, int b)                            { return (int)nl_ret(nl_syscall6(SYS_dup2_, a, b, 0, 0, 0, 0)); }
int   poll(void *fds, unsigned long n, int timeout) { return (int)nl_ret(nl_syscall6(SYS_poll_, (long)fds, (long)n, timeout, 0, 0, 0)); }
int   fcntl(int fd, int cmd, long arg)              { return (int)nl_ret(nl_syscall6(SYS_fcntl_, fd, cmd, arg, 0, 0, 0)); }
int   ioctl(int fd, unsigned long req, long arg)    { return (int)nl_ret(nl_syscall6(SYS_ioctl_, fd, (long)req, arg, 0, 0, 0)); }
int   access(const char *p, int mode)               { return (int)nl_ret(nl_syscall6(SYS_access_, (long)p, mode, 0, 0, 0, 0)); }
int   unlink(const char *p)                         { return (int)nl_ret(nl_syscall6(SYS_unlink_, (long)p, 0, 0, 0, 0, 0)); }
int   mkdir(const char *p, int mode)                { return (int)nl_ret(nl_syscall6(SYS_mkdir_, (long)p, mode, 0, 0, 0, 0)); }
int   rmdir(const char *p)                          { return (int)nl_ret(nl_syscall6(SYS_rmdir_, (long)p, 0, 0, 0, 0, 0)); }
int   rename(const char *a, const char *b)          { return (int)nl_ret(nl_syscall6(SYS_rename_, (long)a, (long)b, 0, 0, 0, 0)); }
int   chdir(const char *p)                          { return (int)nl_ret(nl_syscall6(SYS_chdir_, (long)p, 0, 0, 0, 0, 0)); }
int   chmod(const char *p, int mode)                { return (int)nl_ret(nl_syscall6(SYS_chmod_, (long)p, mode, 0, 0, 0, 0)); }
int   madvise(void *p, unsigned long len, int adv)  { return (int)nl_ret(nl_syscall6(SYS_madvise_, (long)p, (long)len, adv, 0, 0, 0)); }
/* The two durability primitives. A freestanding target cannot borrow
 * them from a host, and they are exactly one syscall each: fsync(2) is
 * the barrier a write-ahead log needs before it may acknowledge a write,
 * and truncate(2) is how recovery cuts a torn tail back off. Under the
 * unikernel both become device work (a virtio-blk flush, a metadata
 * update) and every caller stays put. */
int   fsync(int fd)                                 { return (int)nl_ret(nl_syscall6(SYS_fsync_, fd, 0, 0, 0, 0, 0)); }
int   truncate(const char *p, long long len)        { return (int)nl_ret(nl_syscall6(SYS_truncate_, (long)p, (long)len, 0, 0, 0, 0)); }
int   mprotect(void *p, unsigned long len, int prot) { return (int)nl_ret(nl_syscall6(SYS_mprotect_, (long)p, (long)len, prot, 0, 0, 0)); }
/* The kernel's own CSPRNG. runtime_bare.c's nurl_rand_fill is the only
 * caller and it treats any failure as fatal, so nothing here needs a
 * /dev/urandom fallback — a source that cannot answer is a machine that
 * must not generate keys. Under the unikernel this wrapper becomes
 * RDRAND/RDSEED (or virtio-rng) and every caller stays put. */
long long getrandom(void *buf, unsigned long len, unsigned int flags) {
    return nl_ret(nl_syscall6(SYS_getrandom_, (long)buf, (long)len, flags, 0, 0, 0));
}
int   nanosleep(const void *req, void *rem)         { return (int)nl_ret(nl_syscall6(SYS_nanosleep_, (long)req, (long)rem, 0, 0, 0, 0)); }
int   clock_gettime(int clk, void *ts)              { return (int)nl_ret(nl_syscall6(SYS_clock_gettime_, clk, (long)ts, 0, 0, 0, 0)); }
void  _exit(int code)                               { nl_exit_group(code); for (;;) { } }
