/*
 * NURL nolibc — unikernel/nolibc/tls_linux.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Thread-local storage setup, and the C half of process entry.
 *
 * `stdlib/runtime_core.c` declares twelve `__thread` variables (the
 * panic journal's per-thread state among them). On a hosted target the
 * C runtime startup builds the thread control block before main; with
 * -nostdlib nobody does, so the first access to any of them reads
 * through an fs base of zero and the process dies before printing a
 * character. This file is what a libc owes the compiler for the
 * `__thread` keyword.
 *
 * x86_64 uses TLS variant II: the thread pointer sits ABOVE the static
 * TLS block, each variable lives at a negative offset from it, and
 * fs:0 must hold the thread pointer itself (compilers emit
 * `mov %fs:0,%rax` to materialise it). So the layout is
 *
 *     [ tls image | .tbss ][ TCB: self-pointer, then room ]
 *     ^ block                ^ thread pointer = fs base
 *
 * The image's address and size come from the program headers, found
 * through the auxiliary vector the kernel leaves above envp — the same
 * route musl takes. Reading them at run time rather than baking in
 * linker symbols means this keeps working when the runtime gains or
 * loses a `__thread` variable.
 *
 * The unikernel target keeps every line of this except the auxv walk:
 * there the boot shim knows the TLS bounds from the linker script and
 * writes the fs base with WRMSR instead of arch_prctl.
 */
#include "nolibc.h"

extern void nl_exit_group(int code);
extern int main(int argc, char **argv);

#define AT_NULL   0
#define AT_PHDR   3
#define AT_PHENT  4
#define AT_PHNUM  5
#define PT_TLS    7
#define SYS_arch_prctl 158
#define ARCH_SET_FS 0x1002

/* Elf64_Phdr, the four fields this needs. */
struct nl_phdr {
    unsigned int   p_type;
    unsigned int   p_flags;
    unsigned long  p_offset;
    unsigned long  p_vaddr;
    unsigned long  p_paddr;
    unsigned long  p_filesz;
    unsigned long  p_memsz;
    unsigned long  p_align;
};

/* One thread, so one static block. 8 KiB is far more than the runtime's
 * `__thread` set needs (measured: well under 1 KiB) and the overflow is
 * checked rather than assumed — a silently truncated TLS image would
 * corrupt whichever variable landed last. */
#define NL_TLS_MAX 8192
static unsigned char nl_tls_block[NL_TLS_MAX] __attribute__((aligned(64)));

static void nl_die(const char *msg) {
    extern nl_ssize_t nl_write(int fd, const void *buf, nl_size_t n);
    nl_write(2, msg, strlen(msg));
    nl_exit_group(127);
}

/* Entry from start_x86_64.S with the untouched stack pointer: the
 * kernel's frame is argc, argv[], NULL, envp[], NULL, auxv[]. */
void nl_start_c(long *sp) {
    long argc = sp[0];
    char **argv = (char **)(sp + 1);
    char **envp = argv + argc + 1;
    unsigned long *auxv;
    const struct nl_phdr *phdr = 0;
    unsigned long phnum = 0, phent = sizeof(struct nl_phdr);
    unsigned long i, tls_size = 0, tls_align = 8, tls_filesz = 0;
    const unsigned char *tls_image = 0;
    unsigned char *tp;

    nl_environ = envp;

    { char **e = envp; while (*e) e++; auxv = (unsigned long *)(e + 1); }
    for (i = 0; auxv[i] != AT_NULL; i += 2) {
        if (auxv[i] == AT_PHDR)  phdr  = (const struct nl_phdr *)auxv[i + 1];
        if (auxv[i] == AT_PHNUM) phnum = auxv[i + 1];
        if (auxv[i] == AT_PHENT) phent = auxv[i + 1];
    }
    if (phdr) {
        for (i = 0; i < phnum; i++) {
            const struct nl_phdr *p =
                (const struct nl_phdr *)((const unsigned char *)phdr + i * phent);
            if (p->p_type != PT_TLS) continue;
            tls_image  = (const unsigned char *)p->p_vaddr;
            tls_filesz = p->p_filesz;
            tls_size   = p->p_memsz;
            tls_align  = p->p_align ? p->p_align : 8;
            break;
        }
    }

    /* Round the block up to the segment's alignment, then place the
     * thread pointer immediately after it. */
    tls_size = (tls_size + tls_align - 1) & ~(tls_align - 1);
    if (tls_size + 64 > NL_TLS_MAX)
        nl_die("nolibc: TLS image larger than NL_TLS_MAX\n");

    tp = nl_tls_block + tls_size;
    tp = (unsigned char *)(((unsigned long)tp + tls_align - 1) & ~(tls_align - 1));
    if (tls_filesz) memcpy(tp - tls_size, tls_image, tls_filesz);
    if (tls_size > tls_filesz) memset(tp - tls_size + tls_filesz, 0, tls_size - tls_filesz);
    *(void **)tp = tp;                          /* fs:0 = the thread pointer */

    if (nl_syscall6(SYS_arch_prctl, ARCH_SET_FS, (long)tp, 0, 0, 0, 0) < 0)
        nl_die("nolibc: arch_prctl(ARCH_SET_FS) failed\n");

    exit(main((int)argc, argv));
}
