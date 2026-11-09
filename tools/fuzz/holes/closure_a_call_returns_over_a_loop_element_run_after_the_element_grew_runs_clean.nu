// closure_a_call_returns_over_a_loop_element_run_after_the_element_grew_runs_clean: agora #483 — `( mk x )` over a `~` loop's element kept past the loop; the element's own buffer grows, then the closure runs while the Vec lives
// The shape the fix must keep: a copy of the element's handle survives the element's own growth (agora #483).
// main 21a0fb5: refused (a false positive).
// map: §2.11 | A2 | runs-clean | - | agora #483: a closure a call returns over a loop element run after the element grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk String s → ( @ i ) { ^ \ → i { ^ ( string_len s ) } }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string whose buffer moves while a callee's closure holds its handle` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    ~ x t { = f ( mk x ) }
    ( string_push_str ( vec_at [String] t 0 ) ` and grows past its first capacity, moving its bytes elsewhere` )
    ( nurl_println_int ( f ) )
    ^ 0
}
