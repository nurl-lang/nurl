// cursor_payload_field_view_kept_past_its_arm: agora #336 — a view of a cursor payload's field stored into an outer holder inside a `??` arm, read after the arm while the option still owns the payload (the shape the fix must keep).
// A SAFE program refused: #336 accepted it by handing the field view to the matched owner, but nurlc does not end that view when the owner's payload changes in place through a second match (agora #409). Refused again until #411 ends it there; then this runs clean.
// main: rejected (github#1519 to github#<this revert>: accepted).
// map: §2.10 | A2 | rejected | - | agora #336, #409: a view of a cursor payload's field kept past its arm (safe; refused until #411)
$ `stdlib/core/string.nu`

: W { s v }
: H { String name }

@ mk → ?H { ^ @ ?H { T @ H { ( string_from `the option's payload's name, alive` ) } } }

@ main → i {
    : ?H oh ( mk )
    : ~ W w @ W { `literal` }
    ?? oh {
        T p → { = w @ W { ( string_data . p name ) } }
        F → {}
    }
    ( nurl_println . w v )
    ^ 0
}
