// option_payload_vec_field_element_lent_back:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #762.
// map: §7.6 | A2 | runs-clean | - | agora #762: `?? o { T h → ^ ( vec_at [String] . h items 0 ) }`, o a local `?H`: an element of a payload's Vec field handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ g → String {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) )
    : ?H o @ ?H { T @ H { v 1 } }
    ?? o { T h → { ^ ( vec_at [String] . h items 0 ) } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( g )
    ( nurl_println ( string_data s ) )
    ^ 0
}
