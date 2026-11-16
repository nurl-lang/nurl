// option_payload_nested_field_viewed_while_a_copy_of_the_field_through_a_second_match_grows_it: a view of `. . a child x`; a second match binds `: ~ Inner b . a2 child` and grows `. b x`
// Closed: an owner reached through a borrow of a field path of it is visited at that path below it: the change at `. b x`, b a copy of `. a2 child`, is at `.child.x` in the option's payload (bck_borrow_sweep; agora #874, CodeRabbit's review of github#1913).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a view of `. . a child x`; a second match binds `: ~ Inner b . a2 child` and grows `. b x`
$ `stdlib/core/string.nu`

: Inner { String x }
: Outer { Inner child i n }

@ run i k → v {
    : ~ ? Outer o @ ?Outer { T @ Outer { @ Inner { ( string_from `an inner value long enough for the heap here` ) } 1 } }
    ?? o { T a → {
            : s v ( string_data . . a child x )
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
