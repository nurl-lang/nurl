// A Vec of shares may hold the same Rc value as a bare handle: a helper
// that moves the buffer of the payload it reaches through the Vec ends
// the views taken through the other handle (agora #712).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ grow ( Vec ( Rc ( Vec u ) ) ) hs → v { ( vec_reserve [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) ) 4096 ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( grow hs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
