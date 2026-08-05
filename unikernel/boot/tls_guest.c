/*
 * NURL unikernel — unikernel/boot/tls_guest.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The thread pointer, for a machine with no auxv.
 *
 * `__thread` is a libc service (nolibc finding #22): runtime_core.c
 * declares twelve of them, and with -nostdlib nobody builds the thread
 * control block, so the first access reads through an fs base of zero
 * and the machine dies before printing a character. nolibc's Linux
 * version walks the auxv for PT_TLS to find the image; there is no
 * auxv here, so the bounds come from the linker script instead — same
 * layout (variant II: the image sits BELOW the thread pointer, fs:0
 * points at itself), one less indirection.
 *
 * MSR_FS_BASE is written directly. arch_prctl is a syscall, and the
 * whole point of this file is that there is nothing to call.
 */

extern unsigned char __tls_image_start[];
extern unsigned char __tls_image_end[];
extern unsigned char __tls_memsz_end[];

void pf_panic(const char *msg);

#define TLS_MAX 8192
static unsigned char tls_block[TLS_MAX] __attribute__((aligned(64)));

static void wrmsr(unsigned int msr, unsigned long value) {
    unsigned int lo = (unsigned int)value, hi = (unsigned int)(value >> 32);
    __asm__ __volatile__("wrmsr" :: "c"(msr), "a"(lo), "d"(hi));
}

void nl_tls_init_guest(void) {
    unsigned long filesz = (unsigned long)(__tls_image_end - __tls_image_start);
    unsigned long memsz  = (unsigned long)(__tls_memsz_end - __tls_image_start);
    unsigned long size   = (memsz + 63) & ~63UL;
    unsigned char *tp;
    unsigned long i;

    if (size + 64 > TLS_MAX)
        pf_panic("TLS image larger than the guest's block");

    tp = tls_block + size;
    tp = (unsigned char *)(((unsigned long)tp + 63) & ~63UL);

    for (i = 0; i < filesz; i++) (tp - size)[i] = __tls_image_start[i];
    for (i = filesz; i < size; i++) (tp - size)[i] = 0;
    *(void **)tp = tp;                       /* fs:0 must point at itself */

    wrmsr(0xC0000100 /* IA32_FS_BASE */, (unsigned long)tp);
}
