// view_of_an_inner_string_kept_across_a_loop_clearing_rows_through_their_loop_element: agora #350 — a view of a String in `vv`'s first row, then `~ e vv { ( vec_clear [String] e ) }`; the view read after the loop
// Closed: a change made through a `~` loop's element is made to an element of what the loop iterates (`fe_`): its elements dropped end the borrows of the container's elements (agora #350, #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #350: a view of an inner String kept across a loop that clears each row through its loop element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string cleared by the loop below` ) )
    ( vec_push [( Vec String )] vv r0 )
    : ( Vec String ) row ( vec_at [( Vec String )] vv 0 )
    : String e0 ( vec_at [String] row 0 )
    : s v ( string_data e0 )
    ~ e vv { ( vec_clear [String] e ) }
    ( nurl_println v )
    ^ 0
}
