// cursor_field_view_kept_past_a_push_through_a_second_match: agora #409 — a view of a cursor payload's String field kept past its arm, then the field grown in place through a second ?? of the same option
// Closed: a cursor payload's field view ends with its arm again; #336 handed it to the matched owner, which a change of the payload made in place through a second match does not end (agora #409, claude-formal's HOLD on github#1519).
// main: accepted (since github#1519); AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #409: a view of a cursor payload's String field kept past its arm, then the field grown in place through a second ?? of the same option
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the option payload name, alive and long enough` ) } } }

@ main → i {
    : ~ ? H oh ( mk )
    : ~ W w @ W { `literal` }
    ?? oh { T p → { = w @ W { ( string_data . p name ) } } F → {} }
    ?? oh { T q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes` ) } F → {} }
    ( nurl_println . w v )
    ^ 0
}
