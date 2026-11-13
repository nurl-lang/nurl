// closures_reading_an_rc_field_or_changing_another_rc_type_beside_a_view_run_clean: a closure that only reads ( rc_get . h a ), and one that replaces an Rc of another type, run beside a slice of the payload read through another handle
// Guard for agora #736's fix: only a change of a payload the view's Rc may share ends it.
// main ff75baea: accepted, clean.
// map: §2.2 | A2 | runs-clean | - | agora #736 guard: closures beside a view through another handle that change nothing of its Rc
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
    : ( Rc ( Vec i ) ) other ( rc_new [( Vec i )] ( vec_new [i] ) )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ i ) f \ → i { ^ ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) }
    : ( @ v ) g \ → v { ( rc_set [( Vec i )] other ( vec_new [i] ) ) }
    ( nurl_println_int ( f ) )
    ( g )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
