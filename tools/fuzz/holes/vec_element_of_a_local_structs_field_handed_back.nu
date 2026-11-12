// vec_element_of_a_local_structs_field_handed_back: agora #749 — `^ ( vec_at [String] . h items 0 )`, h a local struct
// Closed: a call handed a field path is asked, at the return, about the binding the field belongs to, as a payload chain's root is: what it lent out of a local struct (or a `sink` one) is copied out and the struct released (mem_ret_local_lend, __roots_have_field; agora #749).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #749: `^ ( vec_at [String] . h items 0 )`, h a local struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ g → String {
    : H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `a string long enough to live on the heap for sure` ) )
    ^ ( vec_at [String] . h items 0 )
}

@ main → i {
    : String s ( g )
    ( nurl_println ( string_data s ) )
    ^ 0
}
