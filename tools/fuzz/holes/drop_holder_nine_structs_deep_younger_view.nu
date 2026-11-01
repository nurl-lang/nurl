// drop_holder_nine_structs_deep_younger_view: agora #340 — a `% Drop` holder of a view, nine struct layers down, is given a view of a younger String: the String drops first and the holder's destructor reads it.
// Closed: the question "may this drop read a view?" walks every layer, a visited set ending it at a type that holds itself instead of a depth cap that answered "no" nine levels down (__drop_may_read_view, agora #340).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #340: a Drop holder nine struct layers deep given a younger view
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: S1 { W a }
: S2 { S1 a }
: S3 { S2 a }
: S4 { S3 a }
: S5 { S4 a }
: S6 { S5 a }
: S7 { S6 a }
: S8 { S7 a }
: S9 { S8 a }

@ mk9 s v → S9 { ^ @ S9 { @ S8 { @ S7 { @ S6 { @ S5 { @ S4 { @ S3 { @ S2 { @ S1 { @ W { v } } } } } } } } } } }

@ main → i {
    : ~ S9 o ( mk9 `literal` )
    : String s ( string_from `a string declared after o, so dropped before it at the end of main` )
    = o ( mk9 ( string_data s ) )
    ^ 0
}
