// option_vec_payload_element_viewed_while_a_second_match_clears_it: a view of an element of a Vec payload, a second match clears the Vec
// Closed: a change through a `??` payload binding ends the views of the other payload bindings of the same value - by field path, and an enum's only within one variant (bck_borrow_sweep, bck_cursor_follow; agora #874; found by its skeptic pass).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a view of an element of a Vec payload, a second match clears the Vec
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
    : ~ ? ( Vec String ) o @ ?( Vec String ) { T ( vec_new [String] ) }
    ?? o { T a → { ( vec_push [String] a ( string_from `element zero long enough for the heap` ) ) } F → {} }
    ?? o { T a → {
            : s v ( string_data ( vec_at [String] a 0 ) )
            ?? o { T b → { ( vec_clear [String] b ) } F → {} }
            ( nurl_println v )
        } F → {} }
    ^ 0
}
