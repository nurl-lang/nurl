// closure_replacing_an_rc_field_of_a_captured_struct_beside_a_view_through_another_handle_is_refused: a closure gives `. h a` of a captured struct, an ( Rc ( Vec u ) ), a new value with rc_set; a slice of the same payload read through another handle is used after it runs
// Closed: agora #736, a closure's effect on a field path notes the Rc types the path reaches, as the call written there does, so the same-Rc rule asks the replayed row.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #736: a closure replacing an Rc field of a captured struct beside a view through another handle
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ) f \ → v { ( rc_set [( Vec u )] . h a ( vec_new [u] ) ) }
    ( f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
