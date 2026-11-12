// rc_share_held_in_a_vec_handed_to_a_helper_that_grows_its_payload_past_a_view_through_a_clone: `( Vec ( Rc ( Vec u ) ) ) hs` holding `r`, handed to a helper that reserves `( rc_get ( vec_at hs 0 ) )`, while a slice of the payload is taken through `r2`
// Closed: a Vec of shares reaches their Rc (__rc_reach), and the same-Rc rule asks the irealloc summary (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a share held in a Vec handed to a helper that grows the payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
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
