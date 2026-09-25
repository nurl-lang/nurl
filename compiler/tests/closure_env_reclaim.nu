// closure_env_reclaim.nu — inline closure-literal env reclamation
// (docs/MEMORY.md §7.4).
//
// A capturing closure allocates a heap environment block. Written as an
// inline literal passed straight to a call, it belongs to the call site
// and is dropped right after the call, whatever the callee does with it: a
// callee only borrows its closure arguments, and one that keeps a closure
// (a struct field here; `thread_spawn`, `spawn` and a signal handler in
// the runtime) keeps its own copy. This reclaims the common map/callback
// pattern, including the in-loop case that would otherwise leak
// unboundedly. Run under LSan this is leak-clean; under ASan it is free of
// double-free / use-after-free.

$ `stdlib/core/string.nu`

// Invoke-only parameter: `f` is used solely as a call callee.
@ run_it ( @ i ) f → i { ^ ( f ) }

// A callee that STORES the closure keeps its own copy (docs/MEMORY.md
// §7.4): the argument is still the caller's, freed after the call, and the
// copy lives on in `b.cb` until `b` is dropped.
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

    // Stored closure: the literal is freed after the call, the copy in bx
    // lives on — invoking it afterwards must read intact captures, not a
    // freed env — and is dropped with bx.
    : ~ Box bx @ Box { \ → i { ^ 0 } }
    ( stash bx \ → i { ^ + base 100 } )
    : ( @ i ) c . bx cb
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
