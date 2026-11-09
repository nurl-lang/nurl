// closure_a_call_returns_over_a_vec_at_binding_run_after_the_element_grew_runs_clean: agora #483 — a closure a call returns over a `vec_at` binding (`( mk e )`), run while its Vec lives after the element's own buffer moved
// The shape the fix must keep: a copy of the element's handle survives the element's own growth (agora #483).
// main 21a0fb5: refused (a false positive).
// map: §2.11 | A2 | runs-clean | - | agora #483: a closure a call returns over a vec_at binding run after the element grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk String s → ( @ i ) { ^ \ → i { ^ ( strlen ( string_data s ) ) } }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string whose buffer moves while a callee's closure holds its handle` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String e ( vec_at [String] t 0 )
        = f ( mk e )
    }
    ( string_push_str ( vec_at [String] t 0 ) ` and grows past its first capacity, moving its bytes elsewhere` )
    ( vec_push [String] t ( string_from `and the Vec grows too` ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
