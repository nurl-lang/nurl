// join_of_a_closure_over_a_vec_at_binding_and_one_over_an_owner_run_after_the_vec_is_cleared: agora #483 — `f = ? c` (a closure over `e = ( vec_at t 0 )`) (a closure over an owner `o`); `t` cleared; `f` run
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a join of a closure over a vec_at binding and one over an owner, run after the Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i n → b { ^ > n 0 }

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : String o ( string_from `an owner long enough for a heap buffer too` )
    : b c ( pick 1 )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String e ( vec_at [String] t 0 )
        = f ? c \ → i { ^ ( strlen ( string_data e ) ) } \ → i { ^ ( strlen ( string_data o ) ) }
    }
    ( vec_clear [String] t )
    ( nurl_println_int ( f ) )
    ^ 0
}
