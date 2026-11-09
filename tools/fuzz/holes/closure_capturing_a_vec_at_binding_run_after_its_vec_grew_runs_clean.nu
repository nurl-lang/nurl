// closure_capturing_a_vec_at_binding_run_after_its_vec_grew_runs_clean: agora #483 — the binding's block ends, the Vec grows, the closure runs while the Vec lives
// The shape the fix must keep: the container's growth moves no element (agora #483).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #483: a closure capturing a vec_at binding run after its Vec grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string read while its vector lives` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String e ( vec_at [String] t 0 )
        = f \ → i { ^ ( strlen ( string_data e ) ) }
    }
    ( vec_push [String] t ( string_from `the vector grows; the element's handle stays` ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
