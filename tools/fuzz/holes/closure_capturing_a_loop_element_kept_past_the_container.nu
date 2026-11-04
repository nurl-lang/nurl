// closure_capturing_a_loop_element_kept_past_the_container: agora #471 — inside `~ x t`, `= f \ → i { ^ ( strlen ( string_data x ) ) }` captures the element itself; `t` ends at its block's end and `f` is called after
// Closed: the loop's element is gone with its loop: the closure that captured it lets go of its name for `t`'s element (`__bck_fe_retire`), so `t`'s end ends it (agora #471; agora #483's loop spelling).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a closure capturing a loop element, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, captured whole` ) )
        ~ x t { = f \ → i { ^ ( strlen ( string_data x ) ) } }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
