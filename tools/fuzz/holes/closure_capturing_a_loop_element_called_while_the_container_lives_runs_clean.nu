// closure_capturing_a_loop_element_called_while_the_container_lives_runs_clean: agora #471 — inside `~ x t`, a closure captures the element; it is called after the loop while `t` lives (the shape the fix must keep)
// Closed: the closure depends on `t`'s element, and `t` lives (agora #471).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a closure capturing a loop element, called while the container lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string, read by the closure while t lives` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    ~ x t { = f \ → i { ^ ( strlen ( string_data x ) ) } }
    ( nurl_println_int ( f ) )
    ^ 0
}
