// payload_binding_of_an_enum_cleared_by_a_closure_under_a_borrow: agora #460 — a closure `wipe` that matches the captured enum and vec_clears its payload, called while the caller's payload binding lends s0 (claude-holes h05)
// main: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #460: a closure `wipe` that matches the captured enum and vec_clears its payload, called while the caller's payload binding lends s0 (claude-holes h05)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Some ( Vec String ) None }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : E e @ E { Some inner }
    : ( @ v ) wipe \ → v { ?? e { Some ys → { ( vec_clear [String] ys ) } None → {} } }
    ?? e { Some xs → {
            : String s0 ( vec_at [String] xs 0 )
            ( wipe )
            ( nurl_println_int ( string_len s0 ) )
        } None → {} }
    ^ 0
}
