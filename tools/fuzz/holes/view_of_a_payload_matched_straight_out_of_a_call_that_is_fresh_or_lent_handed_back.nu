// view_of_a_payload_matched_straight_out_of_a_call_that_is_fresh_or_lent_handed_back: agora #679 — the same with the call matched directly (`?? ( pick v own ) { T e → { ^ ( string_data . e name ) } … }`): the option is released with the `??` on the fresh path
// Closed: a payload matched straight out of such a call borrows the arguments and may be the call's own storage besides, as a binding bound to the call.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #679: the same with the call matched directly (`?? ( pick v own ) { T e → { ^ ( string_data . e name ) } … }`): the option is released with the `??` on the fresh path
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    ^ ( vec_get [S] v 0 )
}

@ f ( Vec S ) v b own → s {
    ?? ( pick v own ) {
        T e → { ^ ( string_data . e name ) }
        F → { ^ `` }
    }
    ^ ``
}

@ main → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `a lent string long enough to live on the heap, for sure` ) )
    ( nurl_println ( f v T ) )
    ( nurl_println ( f v F ) )
    ^ 0
}
