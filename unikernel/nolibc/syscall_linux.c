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

static int nl_errno_slot;
int *__errno_location(void) { return &nl_errno_slot; }

/* -errno in, -1 out with errno set — the libc convention the runtime
 * expects from read/write/open. */
static long nl_ret(long r) {
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
