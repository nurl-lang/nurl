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
 * The fiber runtime in runtime_ffi.c switches through this primitive
 * wherever it is available (see the NURL_FIBER_OWN_CTX gate there) and
 * falls back to ucontext elsewhere.
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

/* Mach-O gives every C symbol a leading underscore; ELF does not. A
 * basic-asm block writes the assembler-level name, so a bare
 * "callq nurl_ctx_switch" links on Linux and leaves an undefined
 * `nurl_ctx_switch` (no underscore) on macOS. Every symbol named from
 * inside an asm string goes through this. */
#if defined(__APPLE__)
#  define NURL_CTX_SYM(name) "_" #name
#else
#  define NURL_CTX_SYM(name) #name
#endif

typedef struct { void *sp; } nurl_ctx_t;

/* ── ASan fiber annotations ──────────────────────────────────────────
 *
 * ASan tracks stack frames against the one stack it knows a thread has.
 * Code running on a switched-in stack therefore looks like an
 * out-of-bounds write into whatever object backs that stack — a false
 * positive by construction. The annotation pair tells ASan where the
 * stack went: `start` before the switch (naming the destination), and
 * `finish` on arrival. The void** carries the fake stack that
 * detect_stack_use_after_return keeps per stack; passing NULL to
 * `start` means "this stack is being left for good", which is how a
 * finished fiber gets its fake stack destroyed instead of leaked.
 *
 * ucontext callers need none of this — ASan intercepts swapcontext and
 * annotates it internally. These are for switches through
 * nurl_ctx_switch, which no interceptor can see.
 *
 * Compiled to empty calls in an uninstrumented build. */
#if defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    define NURL_CTX_ASAN 1
#  endif
#endif
#if defined(__SANITIZE_ADDRESS__)
#  define NURL_CTX_ASAN 1
#endif

#ifdef NURL_CTX_ASAN
/* Declared rather than #included: sanitizer/common_interface_defs.h is
 * not on a freestanding include path, and the ABI is two fixed
 * signatures. __SIZE_TYPE__ is the compiler's own size_t. */
void __sanitizer_start_switch_fiber(void **fake_stack_save,
                                    const void *bottom, __SIZE_TYPE__ size);
void __sanitizer_finish_switch_fiber(void *fake_stack_save,
                                     const void **bottom_old,
                                     __SIZE_TYPE__ *size_old);
#endif

/* About to leave the current stack for [bottom, bottom+size). Pass NULL
 * for fake_save when the current stack is being abandoned for good. */
void nurl_ctx_asan_start_switch(void **fake_save, const void *bottom,
                                unsigned long size)
{
#ifdef NURL_CTX_ASAN
    __sanitizer_start_switch_fiber(fake_save, bottom, (__SIZE_TYPE__)size);
#else
    (void)fake_save; (void)bottom; (void)size;
#endif
}

/* Just arrived on a new stack. `bottom_old`/`size_old` report the stack
 * control came FROM — the only way to learn a thread stack's bounds
 * without libc-specific pthread calls, which is exactly what the fiber
 * side needs in order to name the worker loop's stack on the way back. */
void nurl_ctx_asan_finish_switch(void *fake_save, const void **bottom_old,
                                 unsigned long *size_old)
{
#ifdef NURL_CTX_ASAN
    __SIZE_TYPE__ sz = 0;
    __sanitizer_finish_switch_fiber(fake_save, bottom_old,
                                    size_old ? &sz : (__SIZE_TYPE__ *)0);
    if (size_old) *size_old = (unsigned long)sz;
#else
    (void)fake_save;
    if (bottom_old) *bottom_old = (const void *)0;
    if (size_old)   *size_old   = 0;
#endif
}

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

/* ASan bookkeeping for the test fibers. The main side knows the fiber
 * stack (it is the array right there); the fiber side has to be TOLD
 * where the main stack is, and learns it from the finish call's
 * out-params on its first arrival. */
static void          *nurl__ctx_main_fake;
static void          *nurl__ctx_fib_fake;
static const void    *nurl__ctx_main_lo;
static unsigned long  nurl__ctx_main_size;

/* Called on the FIBER, the instant it gains control.
 *
 * `used` is load-bearing, and for the same reason the trampoline traps
 * with `ud2` instead of calling a helper: the only reference to these
 * two lives inside an asm string, which LTO cannot see. Without it the
 * optimizer concludes they are dead, strips them, and the link fails on
 * an undefined symbol the source plainly contains. */
__attribute__((used))
void nurl__ctx_test_enter(void)
{
    nurl_ctx_asan_finish_switch(nurl__ctx_fib_fake,
                                &nurl__ctx_main_lo, &nurl__ctx_main_size);
}

/* Called on the FIBER, immediately before it hands control back.
 * `used` for the same reason as above. */
__attribute__((used))
void nurl__ctx_test_leave(void)
{
    nurl_ctx_asan_start_switch(&nurl__ctx_fib_fake,
                               nurl__ctx_main_lo, nurl__ctx_main_size);
}

/* Every hook re-inits the one shared fiber context, abandoning whatever
 * fiber was parked in it. The saved fake stack goes with it: the next
 * arrival is a FIRST arrival, and those take NULL. */
static void nurl__ctx_test_init(void (*entry)(void *), void *arg)
{
    nurl__ctx_fib_fake = 0;
    nurl_ctx_init(&nurl__ctx_fiber, nurl__ctx_stack, sizeof nurl__ctx_stack,
                  entry, arg);
}

/* The main-side half of the same pair. */
static void nurl__ctx_test_to_fiber(void)
{
    nurl_ctx_asan_start_switch(&nurl__ctx_main_fake,
                               nurl__ctx_stack, sizeof nurl__ctx_stack);
}
static void nurl__ctx_test_from_fiber(void)
{
    nurl_ctx_asan_finish_switch(nurl__ctx_main_fake, 0, 0);
}

/* A fiber that trashes every callee-saved GPR, hands control back, and
 * then idles. Trashing them is the point: if the switch did not save
 * and restore, the caller would see THESE values instead of its own.
 *
 * The enter/leave calls are ordinary C functions, so the ABI makes them
 * preserve rbx/r12-r15 — the sentinels are still live in the registers
 * at the switch itself, which is what gives the test its teeth. The
 * `subq $8` is not decoration: a function is entered with rsp ≡ 8
 * (mod 16), so calling out from here without it would hand every callee
 * a misaligned stack. */
__attribute__((naked, noinline))
static void nurl__ctx_bounce(void *arg)
{
    __asm__ volatile(
        "subq  $8, %rsp\n\t"
        "callq " NURL_CTX_SYM(nurl__ctx_test_enter) "\n\t"
        "movabsq $0xdeadbeefdeadbeef, %rbx\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r12\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r13\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r14\n\t"
        "movabsq $0xdeadbeefdeadbeef, %r15\n\t"
        "1:\n\t"
        "callq " NURL_CTX_SYM(nurl__ctx_test_leave) "\n\t"
        "leaq " NURL_CTX_SYM(nurl__ctx_fiber) "(%rip), %rdi\n\t"
        "leaq " NURL_CTX_SYM(nurl__ctx_main) "(%rip), %rsi\n\t"
        "callq " NURL_CTX_SYM(nurl_ctx_switch) "\n\t"
        "callq " NURL_CTX_SYM(nurl__ctx_test_enter) "\n\t"
        "jmp 1b\n\t"
    );
}

/* Hand control back to whoever switched us in, annotated. Every C test
 * fiber below yields through this. */
static void nurl__ctx_test_yield(void)
{
    nurl__ctx_test_leave();
    nurl_ctx_switch(&nurl__ctx_fiber, &nurl__ctx_main);
    nurl__ctx_test_enter();
}

/* A fiber that sets its own rounding modes before handing control back. */
static void nurl__ctx_fpbounce(void *arg)
{
    (void)arg;
    nurl__ctx_test_enter();
    unsigned       mx = 0x1f80u;              /* default, all masked   */
    unsigned short cw = 0x037fu;              /* x87 default           */
    __asm__ volatile("ldmxcsr %0" :: "m"(mx));
    __asm__ volatile("fldcw   %0" :: "m"(cw));
    for (;;) nurl__ctx_test_yield();
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
    nurl__ctx_test_init(nurl__ctx_bounce, (void *)0UL);
    long ok;
    nurl__ctx_test_to_fiber();
    __asm__ volatile(
        "movabsq $0x1111111111111111, %%rbx\n\t"
        "movabsq $0x2222222222222222, %%r12\n\t"
        "movabsq $0x3333333333333333, %%r13\n\t"
        "movabsq $0x4444444444444444, %%r14\n\t"
        "movabsq $0x5555555555555555, %%r15\n\t"
        "callq   " NURL_CTX_SYM(nurl_ctx_switch) "\n\t"
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
    nurl__ctx_test_from_fiber();
    return ok;
}

/* Same question for the floating-point control words: set a non-default
 * rounding mode, bounce through a fiber that sets its own, and check we
 * get ours back. */
long nurl_ctx_test_fpcw(void)
{
    nurl__ctx_test_init(nurl__ctx_fpbounce, (void *)0UL);
    unsigned mx_before, mx_after;
    unsigned short cw_before, cw_after;
    __asm__ volatile("stmxcsr %0" : "=m"(mx_before));
    __asm__ volatile("fnstcw  %0" : "=m"(cw_before));

    unsigned       mx_ours = (mx_before & ~0x6000u) | 0x6000u;  /* round to zero */
    unsigned short cw_ours = (unsigned short)((cw_before & ~0x0c00u) | 0x0400u);
    __asm__ volatile("ldmxcsr %0" :: "m"(mx_ours));
    __asm__ volatile("fldcw   %0" :: "m"(cw_ours));

    nurl__ctx_test_to_fiber();
    nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);
    nurl__ctx_test_from_fiber();

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
    nurl__ctx_test_enter();
    long n = (long)(unsigned long)arg;
    nurl__ctx_arg_seen = n;
    for (long i = 0; i < n; i++) {
        nurl__ctx_counter++;
        nurl__ctx_test_yield();
    }
    for (;;) {
        nurl__ctx_switches++;
        nurl__ctx_test_yield();
    }
}

long nurl_ctx_test_pingpong(long n)
{
    nurl__ctx_counter  = 0;
    nurl__ctx_switches = 0;
    nurl__ctx_arg_seen = -1;
    nurl__ctx_test_init(nurl__ctx_pingpong, (void *)(unsigned long)n);
    for (long i = 0; i < n + 1; i++) {
        nurl__ctx_test_to_fiber();
        nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);
        nurl__ctx_test_from_fiber();
    }
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
    /* The annotation call touches no floating point, so the division
     * below is still the fiber's first FP instruction. */
    nurl__ctx_test_enter();
    volatile double a = 1.0, b = 3.0;
    nurl__ctx_fp_result = a / b;
    for (;;) nurl__ctx_test_yield();
}

/* 1 when a fresh fiber can do arithmetic without trapping and the
 * result is right. */
long nurl_ctx_test_fresh_fp(void)
{
    nurl__ctx_fp_result = 0.0;
    nurl__ctx_test_init(nurl__ctx_fpfresh, (void *)0UL);
    nurl__ctx_test_to_fiber();
    nurl_ctx_switch(&nurl__ctx_main, &nurl__ctx_fiber);
    nurl__ctx_test_from_fiber();
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
