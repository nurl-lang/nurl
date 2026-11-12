// A struct holding a share of an Rc may hold the same Rc value as a bare
// handle of it: a helper handed the struct that clears the payload ends
// the views taken through the other handle (agora #712).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ wipe H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( wipe h )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
