// map: §2.14 | A2 | rejected | - | agora #766: adversarial neighbour of the destructor-as-effect rule (a766_unsafe_in_a_struct_field)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a }
: W { H h i n }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ? > ( slice_len [u] sl ) 0 { : W w @ W { @ H { r } 1 } ( nurl_println_int . w n ) } {}
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
