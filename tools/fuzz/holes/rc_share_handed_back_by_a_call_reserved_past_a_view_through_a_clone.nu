// rc_share_handed_back_by_a_call_reserved_past_a_view_through_a_clone: `( vec_reserve ( rc_get ( pick h ) ) 4096 )` with `@ pick H h → ( Rc ( Vec u ) ) { ^ . h a }`, while a slice of the payload is taken through `r2`
// Closed: a value lent out of a struct is anything the struct reaches, its share's payload included (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a share a call hands back out of a struct, its payload reserved, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ pick H h → ( Rc ( Vec u ) ) { ^ . h a }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( vec_reserve [u] ( rc_get [( Vec u )] ( pick h ) ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
