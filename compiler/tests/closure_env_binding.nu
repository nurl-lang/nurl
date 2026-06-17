// closure_env_binding.nu — env reclamation for `:`-bound capturing
// closures (docs/MEMORY.md §7.4).
//
// A `: f \ → … x …` binding owns a heap env block. The compiler frees it
// at scope exit (and, in a loop body, each iteration) UNLESS the closure
// escapes the frame — returned, stored, captured, detached, or
// decomposed — in which case the consumer owns it. Run under LSan this
// is leak-clean; under ASan it is free of double-free / use-after-free
// (an escaped closure read after the frame would fault if wrongly freed).

$ `stdlib/core/string.nu`

@ run_it ( @ i ) f → i { ^ ( f ) }

// Returns a capturing closure — it ESCAPES, so the env is NOT freed here.
@ adder i n → ( @ i ) { : ( @ i ) g \ → i { ^ + n 100 } ^ g }

: Box { ( @ i ) cb }

@ main → i {
    : i base 10

    // Bound + invoked directly → reclaimed at scope exit.
    : ( @ i ) a \ → i { ^ + base 1 }
    ( nurl_print ( nurl_str_int ( a ) ) ) ( nurl_print `\n` )

    // Bound + passed to a borrowing HOF → reclaimed at scope exit.
    : ( @ i ) b \ → i { ^ + base 2 }
    ( nurl_print ( nurl_str_int ( run_it b ) ) ) ( nurl_print `\n` )

    // In a loop: each iteration's binding env is reclaimed (no unbounded
    // leak).
    : ~ i k 0
    ~ < k 3 {
        : ( @ i ) c \ → i { ^ + base k }
        ( nurl_print ( nurl_str_int ( run_it c ) ) ) ( nurl_print `\n` )
        = k + k 1
    }

    // ESCAPE via return: adder returns a closure; this frame owns its env
    // now and frees it explicitly (the env survived — a freed env would
    // fault on the invoke below).
    : ( @ i ) r ( adder 5 )
    ( nurl_print ( nurl_str_int ( r ) ) ) ( nurl_print `\n` )
    : *u re # *u r 1
    ( nurl_free # s re )

    // ESCAPE via store: g is moved into a struct field; not freed at scope
    // exit. Read it back intact, then release its env.
    : ( @ i ) g \ → i { ^ + base 50 }
    : ~ Box bx @ Box { g }
    : ( @ i ) gc . bx cb
    ( nurl_print ( nurl_str_int ( gc ) ) ) ( nurl_print `\n` )
    : *u ge # *u gc 1
    ( nurl_free # s ge )

    ( nurl_print `done\n` )
    ^ 0
}
