// stdlib/std/panic.nu — explicit panic + setjmp/longjmp-based recover
//
// **When to use:**
//   * `panic msg` — abort execution from a place where surfacing an
//     error via `! T E` is not feasible (failed invariant, internal
//     bug, contract violation). If no recover frame is active on this
//     thread, the process aborts with the message to stderr.
//   * `recover closure` — wrap a closure invocation that might panic.
//     Returns Ok(0) on normal completion, Err(PanicInfo) if the closure
//     called `panic`. Use this at HTTP-server handler call sites, in
//     test scaffolds that probe failure paths, or anywhere you'd
//     otherwise want a process-isolated "this could go wrong" boundary.
//
// **What this is NOT:**
//   * It is NOT an exception system. There is no stack unwinding with
//     destructor calls — owned heap allocations made INSIDE the
//     recover scope that do not run their auto-drop simply leak.
//     Recover is a crash-mitigation tool, NOT a routine error path.
//     Always prefer `! T E` + `\` for expected errors.
//   * It does NOT catch SIGSEGV / SIGFPE / SIGBUS / SIGABRT. Signal
//     faults remain process-aborts. Async-signal-safety constraints
//     make bridging signals into the panic model infeasible without
//     making every runtime function async-signal-safe (which they
//     aren't, and shouldn't have to be).
//
// **Typed return shape:**
//   Recover's closure must return void (`(@ v)`). For typed results,
//   capture a `: ~`-mutable binding by-ref and write to it inside the
//   closure BEFORE the panic point (the assignment doesn't run if the
//   panic fires before the closure completes).
//
//   ```
//   : ~ HttpResponse resp ( response_text 500 `internal\n` )
//   : ! v PanicInfo r ( recover \ → v {
//       = resp ( risky_handler req )
//   } )
//   ?? r {
//     T _ → { /* resp holds risky_handler's return value */ }
//     F p → { /* resp holds the default 500; p.msg has the reason */
//             ( panic_info_free p ) }
//   }
//   ```
//
// **Memory cost per panic:** whatever the closure had allocated
// between recover entry and the panic call site leaks. For HTTP
// servers under attack with a buggy handler, this is bounded by
// per-request scratch state — typically a few hundred bytes.

$ `stdlib/core/string.nu`

: PanicInfo {
    String msg
}

@ panic_info_free PanicInfo p → v {
    ( string_free . p msg )
}

// Halt execution with `msg`. If a `recover` frame is active on this
// thread, longjmps to it; the matching `recover` returns Err with `msg`
// captured in PanicInfo.msg. Otherwise prints `msg` to stderr and
// aborts the process. Marked `→ v` (void) but in practice never
// returns to its caller — control either re-enters at recover or dies.
@ panic s msg → v {
    ( nurl_panic msg )
}

// Run `closure` under a recover guard. Closure must be a zero-arg
// void-returning closure (`(@ v)` shape). Returns Ok(0) if the closure
// completed normally, Err(PanicInfo) if it called `panic`. Nested
// recover scopes are supported — `panic` unwinds to the nearest one.
@ recover ( @ v ) closure → ! v PanicInfo {
    // Decompose the closure into (fn_ptr, env_ptr) — the C trampoline
    // calls fn_ptr(env_ptr). Mirrors thread_spawn's shape.
    : *u fnp # *u closure 0
    : *u env # *u closure 1
    : i rv ( nurl_recover fnp env )
    ? == rv 0 {
        ^ @ ! v PanicInfo { T 0 }
    } {}
    // Copy the borrowed message slot into an owned String — the
    // runtime overwrites its slot on the next panic.
    : s raw ( nurl_panic_last_msg )
    : String msg ( string_from raw )
    ^ @ ! v PanicInfo { F @ PanicInfo { msg } }
}
