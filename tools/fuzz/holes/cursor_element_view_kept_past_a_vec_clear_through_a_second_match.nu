// cursor_element_view_kept_past_a_vec_clear_through_a_second_match: agora #409 — a view of an element of a cursor payload's Vec kept past its arm, then the Vec cleared through a second ??
// Closed: a cursor payload's field view ends with its arm again; #336 handed it to the matched owner, which a change of the payload made in place through a second match does not end (agora #409, claude-formal's HOLD on github#1519).
// main: accepted (since github#1519); AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #409: a view of an element of a cursor payload's Vec kept past its arm, then the Vec cleared through a second ??
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ mk → ?( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `the first element of the option's Vec, long enough` ) )
    ^ @ ?( Vec String ) { T v }
}

@ main → i {
    : ~ ? ( Vec String ) ov ( mk )
    : ~ W w @ W { `literal` }
    ?? ov { T p → { = w @ W { ( string_data ( vec_at [String] p 0 ) ) } } F → {} }
    ?? ov { T q → { ( vec_clear [String] q ) } F → {} }
    ( nurl_println . w v )
    ^ 0
}
