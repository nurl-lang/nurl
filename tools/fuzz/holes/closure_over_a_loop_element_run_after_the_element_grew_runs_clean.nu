// closure_over_a_loop_element_run_after_the_element_grew_runs_clean: agora #483 — a closure over a `~` loop's String element, kept past the loop, run after that String grew through `( vec_at t 0 )`
// The shape the fix must keep: a copy of the element's handle survives the element's own growth (agora #483).
// main 21a0fb5: refused (a false positive).
// map: §2.11 | A2 | runs-clean | - | agora #483: a closure over a loop element run after the element grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string whose buffer moves while the closure holds its handle` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    ~ x t { = f \ → i { ^ ( string_len x ) } }
    ( string_push_str ( vec_at [String] t 0 ) ` and grows past its first capacity, moving its bytes elsewhere` )
    ( nurl_println_int ( f ) )
    ^ 0
}
