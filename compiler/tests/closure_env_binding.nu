// closure_env_binding.nu — env reclamation for `:`-bound capturing
// closures (docs/MEMORY.md §7.4).
//
// A `: f \ → … x …` binding owns a heap env block, and the compiler frees
// it at scope exit (and, in a loop body, each iteration). Nothing the
// closure is handed to changes that: a function that returns a closure
// hands its caller an env the caller owns, and a struct field that keeps
// one keeps its own copy, so every place that holds an env drops it and
// no program writes a free. Run under LSan this is leak-clean; under ASan
// it is free of double-free / use-after-free (a closure read after its env
// was wrongly freed would fault).

$ `stdlib/core/string.nu`

@ run_it ( @ i ) f → i { ^ ( f ) }

// Returns a capturing closure: the env moves out to the caller.
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

    // Returned: adder hands its env over; this binding owns it and drops it
    // at scope exit (the env survived the callee's frame — a freed env
    // would fault on the invoke below).
    : ( @ i ) r ( adder 5 )
    ( nurl_print ( nurl_str_int ( r ) ) ) ( nurl_print `\n` )

    // Stored: the struct field keeps its own copy of g, dropped with bx;
    // g's env is g's, dropped with g. Read it back intact through a
    // borrowing binding.
    : ( @ i ) g \ → i { ^ + base 50 }
    : ~ Box bx @ Box { g }
    : ( @ i ) gc . bx cb
    ( nurl_print ( nurl_str_int ( gc ) ) ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
