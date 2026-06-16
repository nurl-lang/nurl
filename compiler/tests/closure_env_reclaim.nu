// closure_env_reclaim.nu — inline closure-literal env reclamation
// (docs/MEMORY.md §7.4).
//
// A capturing closure allocates a heap environment block that auto-drop
// never owns. When the closure is written as an inline literal passed
// DIRECTLY to a parameter the callee only ever invokes (an "invoke-only"
// parameter — a pure borrow), the caller frees that env after the call.
// This reclaims the common map/callback pattern, including the in-loop
// case that would otherwise leak unboundedly. Run under LSan this is
// leak-clean; under ASan it is free of double-free / use-after-free.
//
// `recover` and `thread_spawn` DECOMPOSE the closure (extract its raw
// fn/env pointers), so their parameters are not invoke-only and are left
// alone — the env is reclaimed by recover itself / kept alive for the
// worker thread. Those paths are covered by recover_basic / the thread
// tests; here we pin the invoke-only reclamation and the sound exclusion
// of a callee that stores the closure.

$ `stdlib/core/string.nu`

// Invoke-only parameter: `f` is used solely as a call callee.
@ run_it ( @ i ) f → i { ^ ( f ) }

// A callee that STORES the closure must NOT have its arg's env freed —
// the stored closure (and its env) outlives the call. `b.cb` is written,
// so `f` is value-read → not invoke-only.
: Box { ( @ i ) cb }
@ stash inout Box b ( @ i ) f → v { = . b cb f }

@ main → i {
    : i base 10

    // Inline capturing literal to a borrowing HOF — env freed after.
    : i r ( run_it \ → i { ^ + base 1 } )
    ( nurl_print ( nurl_str_int r ) ) ( nurl_print `\n` )

    // In a loop: each iteration's env is reclaimed (no unbounded leak).
    : ~ i k 0
    ~ < k 4 {
        : i z ( run_it \ → i { ^ + base k } )
        ( nurl_print ( nurl_str_int z ) ) ( nurl_print `\n` )
        = k + k 1
    }

    // Stored closure: its env is NOT freed after the call (it lives on in
    // bx) — invoking it afterwards must read intact captures, not a freed
    // env. The stored env is the caller's to release (manual handle); we
    // free it explicitly to keep the test leak-clean.
    : ~ Box bx @ Box { \ → i { ^ 0 } }
    ( stash bx \ → i { ^ + base 100 } )
    : ( @ i ) c . bx cb
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )
    : *u cenv # *u c 1
    ( nurl_free # s cenv )

    ( nurl_print `done\n` )
    ^ 0
}
