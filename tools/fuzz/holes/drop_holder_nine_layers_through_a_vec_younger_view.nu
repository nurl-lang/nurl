// drop_holder_nine_layers_through_a_vec_younger_view: agora #340 — a `% Drop` holder of a view sits nine layers down, one of them a Vec, and is given a view of a younger String: the String drops first and the holder's destructor reads it.
// Closed: the question "may this drop read a view?" walks every layer — struct fields, Vec and Box elements, option payloads — with a visited set instead of a depth cap (__drop_may_read_view, agora #340).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #340: a Drop holder nine layers deep through a Vec given a younger view
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: T1 { ( Vec W ) a }
: T2 { T1 a }
: T3 { T2 a }
: T4 { T3 a }
: T5 { T4 a }
: T6 { T5 a }
: T7 { T6 a }
: T8 { T7 a }

@ main → i {
    : ( Vec W ) w0 ( vec_new [W] )
    ( vec_push [W] w0 @ W { `literal` } )
    : ~ T8 o @ T8 { @ T7 { @ T6 { @ T5 { @ T4 { @ T3 { @ T2 { @ T1 { w0 } } } } } } } }
    : String s ( string_from `a string declared after o, so dropped before it at the end of main` )
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { ( string_data s ) } )
    = o @ T8 { @ T7 { @ T6 { @ T5 { @ T4 { @ T3 { @ T2 { @ T1 { ws } } } } } } } }
    ^ 0
}
