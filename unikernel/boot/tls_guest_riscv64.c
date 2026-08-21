/*
 * NURL unikernel — unikernel/boot/tls_guest_riscv64.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The thread pointer, for a machine with no auxv — RISC-V.
 *
 * Same job as tls_guest.c, different ABI. RISC-V uses TLS variant I with NO
 * reserved block at all: the thread pointer register (tp, x4) points
 * AT the image, so the first thread-local sits at tp + 0 — where
 * AArch64 leaves sixteen bytes for the runtime. x86-64's variant II has the image BELOW the
 * pointer with tp[0] pointing at itself. Get this backwards and every
 * `__thread` read lands in the reserved words or past the block — a
 * wrong value, not a crash, which is the worst way to be wrong.
 *
 * And the rounding is exactly the part that is easy to get wrong from
 * the documentation: the offset depends on the PT_TLS alignment the
 * LINKER chose, which depends on this program's own variables and on
 * the linker script. So it is MEASURED, not derived: a canary
 * `__thread` variable is read back after the image is placed, and the
 * placement is accepted only when the compiler's own addressing finds
 * the value the image says is there. If no candidate works the machine
 * says so and stops, rather than running with every thread-local off
 * by sixteen bytes.
 *
 * `tp` is an ordinary register here, not a system register: it is
 * written with a `mv`, and there is no syscall to make on a machine
 * with no kernel.
 */

extern unsigned char __tls_image_start[];
extern unsigned char __tls_image_end[];
extern unsigned char __tls_memsz_end[];

void pf_panic(const char *msg);

#define TLS_MAX 8192
static unsigned char tls_block[TLS_MAX] __attribute__((aligned(64)));

/* The canary. Its value is in the .tdata image, so reading it through
 * the compiler's own TLS addressing is a direct test of "is the image
 * where the compiler thinks it is". Volatile so the read is not
 * constant-folded from the initializer. */
static __thread volatile unsigned long tls_canary = 0x4E55524CC0FFEEULL;

/* Read the canary through the compiler's own TLS addressing — in its own
 * function, and one the optimiser may not inline. Same reason as the
 * AArch64 port: LLVM treats the thread pointer as invariant, nothing
 * tells it the `mv tp` below installs the value the read depends on, and
 * LLVM 21 (zig 0.16) materialises the address before the install where
 * LLVM 18 did not. The guest faulted on the stale address before
 * printing a line. The function boundary is the fix — the address is
 * formed in this function, which runs after the call. */
static __attribute__((noinline)) int tls_canary_agrees(void) {
    return tls_canary == 0x4E55524CC0FFEEULL;
}

void nl_tls_init_guest(void) {
    unsigned long filesz = (unsigned long)(__tls_image_end - __tls_image_start);
    unsigned long memsz  = (unsigned long)(__tls_memsz_end - __tls_image_start);
    unsigned char *tp = tls_block;
    unsigned long cand;
    unsigned long i;

    __asm__ __volatile__("mv tp, %0" :: "r"((unsigned long)tp) : "memory");

    /* tp + 16 rounded up to the alignment the linker picked. 16 is the
     * unrounded case; the rest are the alignments a PT_TLS segment
     * plausibly has, smallest first, so the first hit is the right one
     * rather than a larger one that happens to also contain the
     * canary. */
    /* 0 first: this ABI puts the image AT the thread pointer. The rest
     * are here because the offset is measured, not assumed — the same
     * canary check the AArch64 port uses, and the reason it exists is
     * that this number differs between the two ABIs by exactly the
     * kind of amount that reads as plausible garbage. */
    static const unsigned long candidates[] = { 0, 16, 32, 64, 128, 256, 512, 1024 };
    for (unsigned long c = 0; c < sizeof candidates / sizeof candidates[0]; c++) {
        cand = candidates[c];
        if (cand + memsz > TLS_MAX) break;
        unsigned char *img = tp + cand;
        for (i = 0; i < filesz; i++) img[i] = __tls_image_start[i];
        for (i = filesz; i < memsz; i++) img[i] = 0;
        if (tls_canary_agrees()) return;   /* the compiler agrees */
    }
    pf_panic("cannot place the TLS image where this build addresses it "
             "— no candidate offset from the thread pointer holds the "
             "canary (a linker with an unexpected PT_TLS alignment?)");
}
