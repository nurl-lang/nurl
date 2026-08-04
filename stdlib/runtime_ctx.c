/*
 * NURL runtime — stdlib/runtime_ctx.c   (portable stackful context switch)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * A libc-free replacement for getcontext/makecontext/swapcontext.
 *
 * WHY THIS EXISTS
 *
 *   1. The fiber runtime in runtime_ffi.c is gated on ucontext, which
 *      musl does not ship. A musl-built toolchain therefore has NO
 *      async today — the whole fiber block compiles out to stubs. This
 *      primitive depends on nothing but the instruction set.
 *   2. swapcontext saves and restores the signal mask, which costs a
 *      sigprocmask SYSCALL on every switch. A cooperative scheduler
 *      that never touches signals pays that for nothing.
 *   3. A freestanding target has no ucontext at all, so the unikernel
 *      work needs this regardless.
 *
 * It is deliberately NOT wired into the fiber runtime yet: this file
 * lands with its own tests first, so the switch is proven in isolation
 * before anything depends on it.
 *
 * WHAT MUST BE SAVED (x86_64 System V)
 *
 *   Callee-saved GPRs: rbx, rbp, r12, r13, r14, r15, and rsp.
 *
 *   AND the two control words: MXCSR and the x87 control word. The ABI
 *   marks their *control* bits callee-saved — rounding mode, flush-to-
 *   zero, and the x87 precision/rounding field. Omitting them is the
 *   classic "works until someone changes the rounding mode" bug: a
 *   fiber that sets round-toward-zero and yields would silently impose
 *   it on whatever runs next, and get someone else's mode back. Two
 *   instructions each way — there is no reason to skip them.
 *
 *   Caller-saved registers need no handling: a context switch happens
 *   at a call boundary, where the compiler has already spilled anything
 *   live across it.
 *
 * STACK LAYOUT built by nurl_ctx_init, from ctx->sp upward:
 *
 *     +0   mxcsr (4 bytes) | +4 x87 control word (2 bytes)   [8 total]
 *     +8   r15
 *     +16  r14
 *     +24  r13   <- entry function
 *     +32  r12   <- entry argument
 *     +40  rbx
 *     +48  rbp
 *     +56  return address -> nurl__ctx_trampoline
 *
 * so the first switch into a fresh context "returns" into the
 * trampoline, which moves r12/r13 into place and calls the entry.
 */

#if defined(__x86_64__) && !defined(_WIN32)
#  define NURL_CTX_X86_64 1
#endif

typedef struct { void *sp; } nurl_ctx_t;

#ifdef NURL_CTX_X86_64

/* The switch itself. Naked: no prologue may touch the stack we are
 * about to swap out from under ourselves. */
__attribute__((naked, noinline))
void nurl_ctx_switch(nurl_ctx_t *save, nurl_ctx_t *restore)
{
    __asm__ volatile(
        "pushq %rbp\n\t"
        "pushq %rbx\n\t"
        "pushq %r12\n\t"
        "pushq %r13\n\t"
        "pushq %r14\n\t"
        "pushq %r15\n\t"
        "subq  $8, %rsp\n\t"          /* scratch for the control words */
        "stmxcsr (%rsp)\n\t"
        "fnstcw  4(%rsp)\n\t"
        "movq  %rsp, (%rdi)\n\t"      /* save->sp = rsp                */
        "movq  (%rsi), %rsp\n\t"      /* rsp = restore->sp             */
        "fldcw   4(%rsp)\n\t"
        "ldmxcsr (%rsp)\n\t"
        "addq  $8, %rsp\n\t"
        "popq  %r15\n\t"
        "popq  %r14\n\t"
        "popq  %r13\n\t"
        "popq  %r12\n\t"
        "popq  %rbx\n\t"
        "popq  %rbp\n\t"
        "ret\n\t"
    );
}

/* First-entry trampoline: r12 holds the argument, r13 the entry point.
 * Entered via `ret`, so on arrival rsp is 16-byte aligned + 8 — exactly
 * what a callee expects after a `call`, which is why nurl_ctx_init
 * aligns the frame the way it does. */
__attribute__((naked, noinline))
static void nurl__ctx_trampoline(void)
{
    __asm__ volatile(
        "movq %r12, %rdi\n\t"
        "callq *%r13\n\t"
        /* A fiber entry must never return: below the frame is not a
         * return address but the bottom of a fresh stack. Trap here
         * rather than `ret` into it.
         *
         * `ud2` and not a call to a diagnostic helper: the only
         * reference to such a helper would live inside this asm string,
         * which the optimizer cannot see, so LTO dead-strips it and the
         * link fails with an undefined symbol. `ud2` needs no symbol and
         * raises SIGILL — unmistakable in a core dump. */
        "ud2\n\t"
    );
}

/* Prepare `ctx` so the first switch into it runs entry(arg) on the
 * given stack. `stack` is the LOW address of the region, `size` its
 * length in bytes. */
void nurl_ctx_init(nurl_ctx_t *ctx, void *stack, unsigned long size,
                   void (*entry)(void *), void *arg)
{
    unsigned char *top = (unsigned char *)stack + size;
    /* 16-align the top, then reserve the 8-slot frame described above.
     * After the trampoline's entry `ret` pops the return address, rsp
     * is 16-aligned — the state a function body expects. */
    unsigned long  t   = (unsigned long)top & ~(unsigned long)15;
    unsigned long *fp  = (unsigned long *)(t - 64);

    fp[0] = 0;                                   /* mxcsr + x87 cw      */
    fp[1] = 0;                                   /* r15                 */
    fp[2] = 0;                                   /* r14                 */
    fp[3] = (unsigned long)entry;                /* r13                 */
    fp[4] = (unsigned long)arg;                  /* r12                 */
    fp[5] = 0;                                   /* rbx                 */
    fp[6] = 0;                                   /* rbp                 */
    fp[7] = (unsigned long)&nurl__ctx_trampoline;/* return address      */

    /* Seed the control words from the CURRENT thread so a fresh fiber
     * starts in the process's rounding mode rather than in whatever
     * zeroing would imply (mxcsr 0 unmasks every SSE exception — the
     * first floating-point operation would trap). */
    __asm__ volatile("stmxcsr %0" : "=m"(*(unsigned *)&fp[0]));
    __asm__ volatile("fnstcw  %0" : "=m"(*(unsigned short *)((char *)&fp[0] + 4)));

    ctx->sp = (void *)fp;
}

int nurl_ctx_available(void) { return 1; }

#else /* !NURL_CTX_X86_64 — other architectures still use ucontext */

void nurl_ctx_switch(nurl_ctx_t *save, nurl_ctx_t *restore)
{
    (void)save; (void)restore;
}

void nurl_ctx_init(nurl_ctx_t *ctx, void *stack, unsigned long size,
                   void (*entry)(void *), void *arg)
{
    (void)ctx; (void)stack; (void)size; (void)entry; (void)arg;
}

int nurl_ctx_available(void) { return 0; }

#endif

/* ── test hooks ──────────────────────────────────────────────────
 *
 * Exercised from compiler/tests/ctx_switch.nu. They live here rather
 * than in the test because only C can observe a register's value
 * across a switch; the NURL side drives them and asserts.
 */

static nurl_ctx_t nurl__ctx_main;
static nurl_ctx_t nurl__ctx_fiber;
static unsigned char nurl__ctx_stack[64 * 1024];
static long nurl__ctx_counter;
static long nurl__ctx_switches;
static long nurl__ctx_arg_seen;

#ifdef NURL_CTX_X86_64

static void nurl__ctx_fpbounce(void *arg);

/* A fiber that trashes every callee-saved GPR, hands control back, and
 * then idles. Trashing them is the point: if the switch did not save
 * and restore, the caller would see THESE values instead of its own. */
__attribute__((naked, noinline))
static void nurl__ctx_bounce(void *arg)
{
    __asm__ volatile(
        "movabsq $0xdeadbeefdeadbeef, %rbx\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r12\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r13\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r14\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r15\n\t"
        "1:\n\t"
        "leaq nurl__ctx_fiber(%rip), %rdi\n\t"
        "leaq nurl__ctx_main(%rip), %rsi\n\t"
        "callq nurl_ctx_switch\n\t"
        "jmp 1b\n\t"
    );
}

/* A fiber that sets its own rounding modes before handing control back. */
static void nurl__ctx_fpbounce(void *arg)
{
    (void)arg;
    unsigned       mx = 0x1f80u;              /* default, all masked   */
    unsigned short cw = 0x037fu;              /* x87 default           */
    __asm__ volatile("ldmxcsr %0" :: "m"(mx));
    __asm__ volatile("fldcw   %0" :: "m"(cw));
    for (;;) nurl_ctx_switch(&nurl__ctx_fiber, &nurl__ctx_main);
}

/* Do the callee-saved GPRs survive a round trip?
 *
 * Written as one asm block on purpose. C-level `register long x
 * __asm__("rbx")` variables are NOT guaranteed to hold their register
 * across a function call — the compiler is free to spill them, so a
 * test built on them measures the compiler's spill choices rather than
 * the switch. Here the sentinels are loaded, the switch is called, and
 * the comparison happens without the compiler touching any of it; the
 * clobber list makes it save whatever it had in those registers.
 */
long nurl_ctx_test_preserve(void)
{
    nurl_ctx_init(&nurl__ctx_fiber, nurl__ctx_stack, sizeof nurl__ctx_stack,
                  nurl__ctx_bounce, (void *)0UL);
    long ok;
    __asm__ volatile(
        "movabsq $0x1111111111111111, %%rbx\n\t"
        "movabsq $0x2222222222222222, %%r12\n\t"
        "movabsq $0x3333333333333333, %%r13\n\t"
        "movabsq $0x4444444444444444, %%r14\n\t"
        "movabsq $0x5555555555555555, %%r15\n\t"
        "callq   nurl_ctx_switch\n\t"
        "xorl    %%eax, %%eax\n\t"
        "movabsq $0x1111111111111111, %%rcx\n\t"
        "cmpq    %%rcx, %%rbx\n\t"
        "jne     1f\n\t"
        "movabsq $0x2222222222222222, %%rcx\n\t"
        "cmpq    %%rcx, %%r12\n\t"
        "jne     1f\n\t"
        "movabsq $0x3333333333333333, %%rcx\n\t"
        "cmpq    %%rcx, %%r13\n\t"
        "jne     1f\n\t"
        "movabsq $0x4444444444444444, %%rcx\n\t"
        "cmpq    %%rcx, %%r14\n\t"
        "jne     1f\n\t"
        "movabsq $0x5555555555555555, %%rcx\n\t"
        "cmpq    %%rcx, %%r15\n\t"
        "jne     1f\n\t"
        "movl    $1, %%eax\n\t"
        "1:\n\t"
        : "=a"(ok)
        : "D"(&nurl__ctx_main), "S"(&nurl__ctx_fiber)
        : "rbx", "r12", "r13", "r14", "r15", "rcx", "memory", "cc");
    return ok;
}

/* Same question for the floating-point control words: set a non-default
 * rounding mode, bounce through a fiber that sets its own, and check we
 * get ours back. */
long nurl_ctx_test_fpcw(void)
{
    nurl_ctx_init(&nurl__ctx_fiber, nurl__ctx_stack, sizeof nurl__ctx_stack,
                  nurl__ctx_fpbounce, (void *)0UL);
    unsigned mx_before, mx_after;
    unsigned short cw_before, cw_after;
    __asm__ volatile("stmxcsr %0" : "=m"(mx_before));
    __asm__ volatile("fnstcw  %0" : "=m"(cw_before));

    unsigned       mx_ours = (mx_before & ~0x6000u) | 0x6000u;  /* round to zero */
    unsigned short cw_ours = (unsigned short)((cw_before & ~0x0c00u) | 0x0400u);
    __asm__ volatile("ldmxcsr %0" :: "m"(mx_ours));
    __asm__ volatile("fldcw   %0" :: "m"(cw_ours));

    nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);

    __asm__ volatile("stmxcsr %0" : "=m"(mx_after));
    __asm__ volatile("fnstcw  %0" : "=m"(cw_after));
    __asm__ volatile("ldmxcsr %0" :: "m"(mx_before));
    __asm__ volatile("fldcw   %0" :: "m"(cw_before));
    return (mx_after == mx_ours) && (cw_after == cw_ours);
}

/* Plain ping-pong, to count switches and prove the entry argument and
 * the fresh-frame path work. */
static void nurl__ctx_pingpong(void *arg)
{
    long n = (long)(unsigned long)arg;
    nurl__ctx_arg_seen = n;
    for (long i = 0; i < n; i++) {
        nurl__ctx_counter++;
        nurl_ctx_switch(&nurl__ctx_fiber, &nurl__ctx_main);
    }
    for (;;) {
        nurl__ctx_switches++;
        nurl_ctx_switch(&nurl__ctx_fiber, &nurl__ctx_main);
    }
}

long nurl_ctx_test_pingpong(long n)
{
    nurl__ctx_counter  = 0;
    nurl__ctx_switches = 0;
    nurl__ctx_arg_seen = -1;
    nurl_ctx_init(&nurl__ctx_fiber, nurl__ctx_stack, sizeof nurl__ctx_stack,
                  nurl__ctx_pingpong, (void *)(unsigned long)n);
    for (long i = 0; i < n + 1; i++)
        nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);
    return nurl__ctx_counter;
}

static volatile double nurl__ctx_fp_result;

/* A fiber that does floating-point arithmetic as its FIRST action,
 * before touching MXCSR. This is what makes the seeding in
 * nurl_ctx_init load-bearing: a zeroed MXCSR unmasks every SSE
 * exception, so an ordinary inexact division (1/3 is not
 * representable) raises #XF and the process dies on SIGFPE. Seeding
 * from the creating thread starts the fiber in the process's own
 * rounding and masking state instead. */
static void nurl__ctx_fpfresh(void *arg)
{
    (void)arg;
    volatile double a = 1.0, b = 3.0;
    nurl__ctx_fp_result = a / b;
    for (;;) nurl_ctx_switch(&nurl__ctx_fiber, &nurl__ctx_main);
}

/* 1 when a fresh fiber can do arithmetic without trapping and the
 * result is right. */
long nurl_ctx_test_fresh_fp(void)
{
    nurl__ctx_fp_result = 0.0;
    nurl_ctx_init(&nurl__ctx_fiber, nurl__ctx_stack, sizeof nurl__ctx_stack,
                  nurl__ctx_fpfresh, (void *)0UL);
    nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);
    double d = nurl__ctx_fp_result - (1.0 / 3.0);
    if (d < 0) d = -d;
    return d < 1e-15;
}

long nurl_ctx_test_arg_seen(void) { return nurl__ctx_arg_seen; }

#else

long nurl_ctx_test_pingpong(long n)  { (void)n; return -1; }
long nurl_ctx_test_preserve(void)    { return -1; }
long nurl_ctx_test_fpcw(void)        { return -1; }
long nurl_ctx_test_arg_seen(void)    { return -1; }
long nurl_ctx_test_fresh_fp(void)    { return -1; }

#endif
