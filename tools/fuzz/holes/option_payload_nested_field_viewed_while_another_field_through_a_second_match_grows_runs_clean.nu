// option_payload_nested_field_viewed_while_another_field_through_a_second_match_grows_runs_clean: a view of `. . a child y`; `. b x` grown through a copy of `. a2 child`: another field
// Closed: an owner reached through a borrow of a field path of it is visited at that path below it: the change at `. b x`, b a copy of `. a2 child`, is at `.child.x` in the option's payload (bck_borrow_sweep; agora #874, CodeRabbit's review of github#1913).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-874: a view of `. . a child y`; `. b x` grown through a copy of `. a2 child`: another field
$ `stdlib/core/string.nu`

: Inner { String x String y }
: Outer { Inner child i n }

@ run i k → v {
    : ~ ? Outer o @ ?Outer { T @ Outer { @ Inner { ( string_from `an inner value long enough for the heap here` ) ( string_from `the y field, long enough for the heap too` ) } 1 } }
    ?? o { T a → {
            : s v ( string_data . . a child y )
            ?? o { T a2 → {
                    : ~ Inner b . a2 child
                    ( string_push_str . b x `, and a long tail appended to grow the buffer past its room and more` )
                } F → {} }
            ( nurl_println v )
        } F → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}
