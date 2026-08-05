// ctx_switch.nu — the portable stackful context switch (runtime_ctx.c).
//
// A libc-free replacement for getcontext/makecontext/swapcontext. It
// matters for three separate reasons: musl ships no ucontext, so a
// musl-built toolchain has no fibers at all today; swapcontext saves
// the signal mask, costing a syscall on every switch a cooperative
// scheduler has no use for; and a freestanding target has neither.
//
// The C side owns the parts only C can do — parking known values in
// callee-saved registers and reading them back after a switch. This
// test drives it and asserts.
//
// The MXCSR / x87 control-word case is the one that is easy to skip and
// expensive to skip: the ABI marks their control bits callee-saved, so
// a fiber that sets round-toward-zero and yields would otherwise impose
// its rounding mode on whatever runs next and inherit someone else's.
//
// requires: fibers
//
// `fibers` because the subject of this test IS the fiber runtime's own
// switch primitive. Where there is no backend for it, the first line
// reads "not implemented on this arch" and every assertion below is
// about something that is not there — a fact docs/ASYNC.md already
// records, not one worth a second golden. Windows is that platform
// until a Win64 backend lands (different ABI: rdi/rsi and XMM6-15 are
// callee-saved, plus the TIB stack fields and the SEH chain).

& `c` @ nurl_ctx_available → i

& `c` @ nurl_ctx_test_pingpong i n → i

& `c` @ nurl_ctx_test_preserve → i

& `c` @ nurl_ctx_test_fpcw → i

& `c` @ nurl_ctx_test_arg_seen → i

& `c` @ nurl_ctx_test_fresh_fp → i

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ main → i {
    // On a non-x86_64 host the primitive is a documented stub and the
    // hooks report -1; the suite still has to pass there, so the
    // assertions are phrased to hold either way.
    : i have ( nurl_ctx_available )
    ? == have 0 {
        ( nurl_print `context switch: not implemented on this arch (ucontext still used)\n` )
        ^ 0
    } {}

    ( pb `primitive is available: ` == have 1 )

    // 1000 round trips. Each one runs the full save/restore path, so a
    // register or control word that is not preserved shows up here
    // rather than after an hour of production traffic.
    : i ran ( nurl_ctx_test_pingpong 1000 )
    ( pb `1000 round trips completed: ` == ran 1000 )
    ( pb `entry argument arrived intact: ` == ( nurl_ctx_test_arg_seen ) 1000 )

    // The fiber deliberately trashes rbx/r12-r15 before yielding, so a
    // switch that failed to save them would hand back 0xdeadbeef.
    ( pb `callee-saved GPRs survive a round trip: ` == ( nurl_ctx_test_preserve ) 1 )
    ( pb `MXCSR + x87 control word survive: ` == ( nurl_ctx_test_fpcw ) 1 )

    // A fresh fiber must be able to do arithmetic before it has touched
    // MXCSR. A zeroed MXCSR unmasks every SSE exception, so an ordinary
    // inexact division would raise #XF and kill the process — which is
    // why nurl_ctx_init seeds the control words from the creating
    // thread rather than leaving them at zero.
    ( pb `fresh fiber can do floating point: ` == ( nurl_ctx_test_fresh_fp ) 1 )

    // Repeat at a different count: a stack frame built once correctly
    // and then reused wrongly would pass the first run only.
    : i ran2 ( nurl_ctx_test_pingpong 7 )
    ( pb `re-init and 7 more round trips: ` == ran2 7 )
    ( pb `argument intact on re-init: ` == ( nurl_ctx_test_arg_seen ) 7 )
    ( pb `regs still preserved after re-init: ` == ( nurl_ctx_test_preserve ) 1 )

    // A single round trip is the degenerate case — the fresh-context
    // entry path with no loop iterations to hide a bad frame.
    : i ran3 ( nurl_ctx_test_pingpong 1 )
    ( pb `single round trip: ` == ran3 1 )
    ^ 0
}
