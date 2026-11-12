// lend_of_a_sink_structs_field_handed_back: agora #749 — `@ g sink H h → String { ^ ( f0 . h a ) }`
// Closed: a call handed a field path is asked, at the return, about the binding the field belongs to, as a payload chain's root is: what it lent out of a local struct (or a `sink` one) is copied out and the struct released (mem_ret_local_lend, __roots_have_field; agora #749).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #749: `@ g sink H h → String { ^ ( f0 . h a ) }`
$ `stdlib/core/string.nu`

: H { String a i n }

@ f0 String p → String { ^ p }

@ g sink H h → String {
    ^ ( f0 . h a )
}

@ main → i {
    : String s ( g @ H { ( string_from `a string long enough to live on the heap for sure` ) 1 } )
    ( nurl_println ( string_data s ) )
    ^ 0
}
