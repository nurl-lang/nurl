// vec_at_binding_vec_field_element_lent_back:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #762.
// map: §7.6 | A2 | runs-clean | - | agora #762: `: H h ( vec_at [H] hs 0 )  ^ ( vec_at [String] . h items 0 )`, hs a local Vec: an element of an element's Vec field handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ g → String {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) )
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { v 1 } )
    : H h ( vec_at [H] hs 0 )
    ^ ( vec_at [String] . h items 0 )
}

@ main → i {
    : String s ( g )
    ( nurl_println ( string_data s ) )
    ^ 0
}
