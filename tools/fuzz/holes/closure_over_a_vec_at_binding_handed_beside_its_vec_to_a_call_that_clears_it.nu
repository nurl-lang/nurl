// closure_over_a_vec_at_binding_handed_beside_its_vec_to_a_call_that_clears_it: agora #483 — `f` over `e = ( vec_at t 0 )`, handed with `t` to a call that clears `t` and then runs `f`
// Closed: `~^t` conflicts with a call that drops `t`'s elements, as `^t` does (bck_alias_conflict, agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding handed beside its Vec to a call that clears it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clear_then_run ( Vec String ) v ( @ i ) g → i { ( vec_clear [String] v ) ^ ( g ) }

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : String e ( vec_at [String] t 0 )
    : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
    ( nurl_println_int ( clear_then_run t f ) )
    ^ 0
}
