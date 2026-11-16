// option_struct_payload_field_viewed_while_a_second_match_grows_another_field_runs_clean: a view of `. a x`, a second match grows `. b y`: another field
// Closed: a change through a `??` payload binding ends the views of the other payload bindings of the same value - by field path, and an enum's only within one variant (bck_borrow_sweep, bck_cursor_follow; agora #874; found by its skeptic pass).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-874: a view of `. a x`, a second match grows `. b y`: another field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: H2 { String x String y }
: | E { EN ES H EV ( Vec String ) }
: W { ?String f1 ?String f2 }

@ id ? String a → ?String { ^ a }
@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }
@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ main → i {
    : ~ ? H2 o @ ?H2 { T @ H2 { ( string_from `field x long enough for the heap allocation` ) ( string_from `field y long enough for the heap allocation` ) } }
    ?? o { T a → {
            : s v ( string_data . a x )
            ?? o { T b → { ( string_push_str . b y `, and a long tail appended to grow the buffer past its room and more` ) } F → {} }
            ( nurl_println v )
        } F → {} }
    ^ 0
}
