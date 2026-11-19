// share_of_a_parameter_handed_to_a_helper_beside_the_parameter_itself: `( save xs h ( rc_clone h ) )` in a helper, `save` pushing its third argument into its first, then the payload replaced through `xs`
// Closed (agora #793): a parameter handed to a call beside a share of itself is no container of that share: the share kept into another parameter argument is this function's to report (__rck_note).
// main 58ab303: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #793: ( save xs h ( rc_clone h ) ) in a helper, save pushing its third argument into its first, then the payload replaced through xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ wipe0 ( Vec ( Rc ( Vec u ) ) ) xs → v { ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) ) }

@ save ( Vec ( Rc ( Vec u ) ) ) xs ( Rc ( Vec u ) ) h0 ( Rc ( Vec u ) ) s → v {
    ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] h0 ) ) )
    ( vec_push [( Rc ( Vec u ) )] xs s )
}

@ addto3 ( Rc ( Vec u ) ) h ( Vec ( Rc ( Vec u ) ) ) xs → v { ( save xs h ( rc_clone [( Vec u )] h ) ) }

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] ) ( addto3 h xs ) ( wipe0 xs ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
