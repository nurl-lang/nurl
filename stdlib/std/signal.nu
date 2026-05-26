// stdlib/std/signal.nu — Signal handling: generic + legacy shutdown.
//
// Two layers in one place, mirroring runtime.c §21:
//
//   (a) Generic per-signum NURL closure handlers.
//
//         ( signal_install   sig handler ) → v
//         ( signal_clear     sig )         → v
//         ( signal_pending   sig )         → b
//         ( signal_poll )                  → i   (lowest pending or -1)
//         ( signal_dispatch )              → v   (run pending handlers)
//         ( signal_raise     sig )         → i   (0 ok)
//         ( signal_pipe_fd )               → i   (read end or -1)
//         ( signal_name      sig )         → s   ("SIGTERM", "SIG#7", …)
//         ( signal_constant  name )        → i   ("SIGUSR1" → 10, … or -1)
//
//   (b) Legacy graceful-shutdown bridge for accept()-loops:
//
//         ( signal_install_shutdown listener ) → v
//         ( signal_clear_shutdown )            → v
//         ( signal_trigger_shutdown )          → v   (test/dev only)
//
// ── Closure shape ────────────────────────────────────────────────
//
// A NURL signal handler takes the signum that fired and returns void:
//
//     : ( @ v i ) on_term \ i sig → v {
//         ( println `caught signal:` )
//         ( println_i sig )
//     }
//     ( signal_install ( signal_constant `SIGTERM` ) on_term )
//
// The same closure can be installed for multiple signums; the signum
// argument lets it discriminate.
//
// ── Async-signal-safety contract ─────────────────────────────────
//
// NURL handlers DO NOT run in the OS signal-context. The OS-level
// handler is implemented in runtime.c and is strictly async-signal-
// safe: it sets a `volatile sig_atomic_t` flag, writes one byte to a
// self-pipe (POSIX), and — for SIGINT/SIGTERM with a registered
// listener — calls `shutdown(2)` on the listener fd. Everything else
// is deferred.
//
// The NURL handler runs on the main thread when the program calls
// `signal_dispatch` (or `signal_poll` + manual handling). At that
// point the program is back in normal NURL mainline code and may:
//
//   * allocate, free, log, lock mutexes, perform I/O
//   * call any stdlib function
//   * panic / recover
//
// Caveats:
//
//   * Signals may coalesce. Two SIGUSR1s arriving back-to-back can
//     be observed as one pending-bit and one dispatch call. The
//     same is true of POSIX signal handlers; if you need lossless
//     delivery, use `signalfd` / a custom event source instead.
//
//   * `signal_dispatch` is NOT auto-called by the runtime. Long-
//     running loops should either:
//       (i)  call it at safe points in their event loop, or
//       (ii) `select`/`poll` on `signal_pipe_fd` and dispatch when
//            the FD becomes readable.
//
//   * Synchronous fault signals (SIGSEGV/SIGBUS/SIGFPE/SIGILL)
//     can be registered but the NURL handler is NOT guaranteed to
//     run — if the faulting frame can't be returned-from, the
//     process aborts before the next dispatch. Use these only for
//     diagnostic dumps; don't rely on them for recovery.
//
//   * Threads: the OS handler can run on ANY thread. The pending
//     bit and self-pipe wake are visible to whichever thread next
//     polls. Handlers themselves run on whichever thread called
//     `signal_dispatch`. Conventional usage is to drive dispatch
//     from the main thread only.
//
// ── Win32 / WASI ────────────────────────────────────────────────
//
// Win32 supports only the CRT subset (SIGINT/SIGTERM/SIGABRT/SIGFPE/
// SIGILL/SIGSEGV) and bridges Ctrl+C/Ctrl+Break/Close to SIGINT via
// SetConsoleCtrlHandler. POSIX-only signums (SIGUSR1/2, SIGHUP, …)
// return -1 from `signal_constant` and -1 from `signal_install` on
// Windows.
//
// WASI has no signals at all; every entry is a no-op stub returning
// -1 / 0 / false as appropriate.

$ `stdlib/std/net.nu`
$ `stdlib/core/posix.nu`  // nurl_native_constant / SIG* lookups

// ── FFI declarations ────────────────────────────────────────────

& `c` @ nurl_signal_register   i sig *u fn *u env → i
& `c` @ nurl_signal_unregister i sig → v
& `c` @ nurl_signal_pending    i sig → i
& `c` @ nurl_signal_poll → i
& `c` @ nurl_signal_dispatch → v
& `c` @ nurl_signal_pipe_fd → i
& `c` @ nurl_signal_raise      i sig → i

// ── Generic API ─────────────────────────────────────────────────

// Install `handler` as the NURL closure that runs when `sig` fires.
// Returns 0 on success, -1 if the signum is unsupported on this
// target. The closure is BORROWED — caller must keep it alive (and
// its captured env block) until the corresponding `signal_clear`.
@ signal_install i sig ( @ v i ) handler → i {
    : *u fnp # *u handler 0
    : *u env # *u handler 1
    ^ ( nurl_signal_register sig fnp env )
}

// Restore the default disposition for `sig` and forget the
// registered closure. Idempotent: clearing an un-registered sig
// is a no-op.
@ signal_clear i sig → v {
    ( nurl_signal_unregister sig )
}

// Non-destructive check: has `sig` fired since the last dispatch?
@ signal_pending i sig → b {
    ^ != 0 ( nurl_signal_pending sig )
}

// Destructive single-signum probe. Returns the lowest pending
// signum and clears its bit, or -1 if none are pending. Useful
// in custom poll loops that want to run their own handler logic
// instead of going through `signal_dispatch`.
@ signal_poll → i {
    ^ ( nurl_signal_poll )
}

// Run every registered NURL handler whose signal is currently
// pending. Pending bits are cleared BEFORE each handler runs, so
// a re-entrant raise of the same signal inside a handler is
// observed on the next dispatch tick.
@ signal_dispatch → v {
    ( nurl_signal_dispatch )
}

// Synthesise a signal to self. Returns 0 on success, -1 on
// invalid signum or unsupported target. Used by tests; production
// callers normally let the OS deliver the signal.
@ signal_raise i sig → i {
    ^ ( nurl_signal_raise sig )
}

// Read end of the self-pipe — level-triggered, one byte per
// delivery. Add it to your select/poll/epoll set to wake a loop
// when a signal arrives without polling the pending bits.
// Returns -1 on Win32/WASI or before the first `signal_install`.
@ signal_pipe_fd → i {
    ^ ( nurl_signal_pipe_fd )
}

// Look up a signal number by canonical name ("SIGINT", "SIGTERM",
// "SIGUSR1", …). Returns -1 if the name is unknown on this target.
// Thin wrapper over `nurl_native_constant` so callers don't need
// to import the runtime FFI directly.
@ signal_constant s name → i {
    ^ ( nurl_native_constant name )
}

// Best-effort signum → static name lookup. Returns `"SIG?"` for
// unrecognised values so the result is always a borrowable string
// literal (no allocation, no free required by caller).
@ signal_name i sig → s {
    ? == sig ( nurl_native_constant `SIGINT`  ) { ^ `SIGINT`  } {}
    ? == sig ( nurl_native_constant `SIGTERM` ) { ^ `SIGTERM` } {}
    ? == sig ( nurl_native_constant `SIGHUP`  ) { ^ `SIGHUP`  } {}
    ? == sig ( nurl_native_constant `SIGQUIT` ) { ^ `SIGQUIT` } {}
    ? == sig ( nurl_native_constant `SIGUSR1` ) { ^ `SIGUSR1` } {}
    ? == sig ( nurl_native_constant `SIGUSR2` ) { ^ `SIGUSR2` } {}
    ? == sig ( nurl_native_constant `SIGPIPE` ) { ^ `SIGPIPE` } {}
    ? == sig ( nurl_native_constant `SIGALRM` ) { ^ `SIGALRM` } {}
    ? == sig ( nurl_native_constant `SIGCHLD` ) { ^ `SIGCHLD` } {}
    ? == sig ( nurl_native_constant `SIGABRT` ) { ^ `SIGABRT` } {}
    ? == sig ( nurl_native_constant `SIGFPE`  ) { ^ `SIGFPE`  } {}
    ? == sig ( nurl_native_constant `SIGILL`  ) { ^ `SIGILL`  } {}
    ? == sig ( nurl_native_constant `SIGSEGV` ) { ^ `SIGSEGV` } {}
    ? == sig ( nurl_native_constant `SIGBUS`  ) { ^ `SIGBUS`  } {}
    ? == sig ( nurl_native_constant `SIGCONT` ) { ^ `SIGCONT` } {}
    ? == sig ( nurl_native_constant `SIGTSTP` ) { ^ `SIGTSTP` } {}
    ? == sig ( nurl_native_constant `SIGWINCH`) { ^ `SIGWINCH`} {}
    ^ `SIG?`
}

// ── Legacy graceful-shutdown bridge ────────────────────────────
//
// `listener` is BORROWED. The runtime stores a single-slot pointer
// to the `NurlTcp` struct; the OS-level signal handler dereferences
// `h->fd` and calls `shutdown(fd, RDWR)`. shutdown(2) is on SUSv4
// §2.4.3's async-signal-safe list, so this happens inline in the
// handler — no `signal_dispatch` call needed for the accept-loop
// wake-up to land. The struct itself is never freed by the handler.
//
// Only one listener can be registered at a time. Pass NULL via
// `signal_clear_shutdown` to forget the registration entirely.

@ signal_install_shutdown TcpListener listener → v {
    : s raw . listener raw
    : i h # i raw
    ( nurl_signal_install_shutdown h )
}

@ signal_clear_shutdown → v {
    ( nurl_signal_install_shutdown 0 )
}

// Test / dev: trigger the same shutdown path the OS-level handler
// would, without actually raising the signal (which on Windows can't
// be delivered programmatically and on POSIX could kill the test
// runner if the registration order is wrong).
@ signal_trigger_shutdown → v {
    ( nurl_signal_trigger_shutdown )
}
