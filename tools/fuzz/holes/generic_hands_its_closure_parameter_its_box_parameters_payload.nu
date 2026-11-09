// generic_hands_its_closure_parameter_its_box_parameters_payload: agora #461 — a generic hands its closure parameter `( box_get [A] b )`
// Closed: a lender whose lend raw provenance makes counts as one whose answer is still owed (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a generic hands its closure parameter its box parameter's payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

@ with0 [A] ( Box A ) b ( @ v A ) f → v {
    ( f ( box_get [A] b ) )
}

@ main → i {
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `a string long enough to live on the heap for sure` ) )
    : ( Box ( Vec String ) ) bx ( box_new [( Vec String )] r0 )
    : ( Vec String ) r ( box_get [( Vec String )] bx )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( with0 [( Vec String )] bx \ ( Vec String ) z → v { ( vec_clear [String] z ) } )
    ( nurl_println d )
    ^ 0
}
