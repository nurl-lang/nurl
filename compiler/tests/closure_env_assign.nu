// closure_env_assign.nu — a capturing closure owns a heap env block, and
// the `=` spelling has to release it exactly as the `:` spelling does.
// Both leaked before: the assignment path never registered the env for
// the function-exit free (16 bytes per assignment, LeakSanitizer), and a
// MOVE between two closure bindings orphaned it in either spelling —
// generating the right-hand side reads the identifier, a value read of a
// closure binding counts as an escape and drops it from the owned set,
// so by the time the transfer ran the source was already gone from the
// list and nothing owned the env.
//
// Every shape below allocates an env. Run under LSAN_DETECT_LEAKS=1 the
// program must report none.

@ pr i v → v { ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

@ main → i {
    : ~ i n 42

    // Assigned once over a non-capturing initial value.
    : ~ ( @ v ) f \ → v {}
    = f \ → v { ( pr n ) }
    ( f )

    // Assigned again: the first env must go before the second lands.
    = f \ → v { ( pr + n 1 ) }
    ( f )

    // Moved out of a `:`-bound closure by `=`.
    : ( @ v ) g \ → v { ( pr + n 2 ) }
    = f g
    ( f )

    // The same move in the `:` spelling.
    : ( @ v ) h \ → v { ( pr + n 3 ) }
    : ( @ v ) h2 h
    ( h2 )

    // One env per iteration, released each time round.
    : ~ i k 0
    ~ < k 2 {
        = f \ → v { ( pr + n k ) }
        ( f )
        = k + k 1
    }
    ^ 0
}
