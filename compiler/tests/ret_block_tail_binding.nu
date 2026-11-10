// `^ { x }` hands the binding back as `^ x` does: a value block is no scope
// of its own. A parameter, a loop's element or a binding that borrows went
// back as the function's own, and its owner and the caller both released it.
$ `stdlib/core/string.nu`

: Rec { String name i n }

@ id_str String p → String { ^ { p } }

@ id_slice [i p → [i { ^ { p } }
@ id_nested String p → String { ^ { { p } } }
@ field_of Rec p → String { : String w . p name ^ { w } }
@ first_of [String nn → String { ~ r nn { ^ { r } } ^ ( string_from `none of them, in a string long enough for the heap` ) }

@ main → i {
    : String a ( string_from `a long enough string to be on the heap, one` )
    : String r1 ( id_str a ) : String r2 ( id_nested a )
    ( nurl_println ( string_data r1 ) ) ( nurl_println ( string_data r2 ) ) ( nurl_println ( string_data a ) )
    : [i q [i | 1 2 3]
    : [i r3 ( id_slice q )
    ~ x r3 { ( nurl_println ( nurl_str_int x ) ) } ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    : Rec rec @ Rec { ( string_from `a long enough string to be on the heap, rec` ) 1 }
    : String r4 ( field_of rec )
    ( nurl_println ( string_data r4 ) ) ( nurl_println ( string_data . rec name ) )
    : [String nn [String | ( string_from `a long enough string to be on the heap, two` ) ( string_from `a long enough string to be on the heap, three` )]
    : String r5 ( first_of nn )
    ( nurl_println ( string_data r5 ) )
    ~ x nn { ( nurl_println ( string_data x ) ) }
    ^ 0
}
