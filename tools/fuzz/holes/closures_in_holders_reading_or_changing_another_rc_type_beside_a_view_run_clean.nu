// closures_in_holders_reading_or_changing_another_rc_type_beside_a_view_run_clean: closures held in a struct, an option and a Vec, a join handed to a helper, a maker's closure in a struct or a builder's, that read an Rc's payload, change an Rc of another type, or replace the payload before the view is taken, run beside a slice taken through another handle
// Guard for agora #736: what a holder's closures do is asked where the holder is handed, not more.
// main 923fa94a: accepted; clean under ASan and strict LSan.
// map: §2.2 | A2 | runs-clean | - | agora #736: closures in holders that read the payload or change another Rc type, beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ runall ( Vec ( @ v ) ) fs → v {
    : ~ i k 0
    ~ < k ( vec_len [( @ v )] fs ) { ?? ( vec_get [( @ v )] fs k ) { T g → { ( g ) } F → {} } = k + k 1 }
}

@ runo ? ( @ v ) o → v { ?? o { T g → { ( g ) } F → {} } }

@ run ( @ v ) f → v { ( f ) }

@ mkread ( Rc ( Vec u ) ) h → ( @ v ) {
    ^ \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] h ) ) ) }
}

@ mkhread ( Rc ( Vec u ) ) h → C { ^ @ C { ( mkread h ) 4 } }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 3 )
    : ( Rc ( Vec i ) ) q ( rc_new [( Vec i )] w0 )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    // A struct's closure that changes an Rc of another type.
    : C c @ C { \ → v { ( rc_set [( Vec i )] q ( vec_new [i] ) ) } 1 }
    ( runc c )
    // …one that only reads the payload.
    : ( Rc ( Vec u ) ) ra ( rc_clone [( Vec u )] r )
    : C d @ C { \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] ra ) ) ) } 2 }
    ( runc d )
    : ( @ v ) g . d go
    ( g )
    : ( Rc ( Vec u ) ) rb ( rc_clone [( Vec u )] r )
    : ?( @ v ) o @ ?( @ v ) { T \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] rb ) ) ) } }
    ( runo o )
    ?? o { T h → { ( h ) } F → {} }
    // A join of closures that read, handed to a helper; a maker's closure
    // that reads, stored in a struct.
    : ( Rc ( Vec u ) ) rc ( rc_clone [( Vec u )] r )
    : ( Rc ( Vec u ) ) rd ( rc_clone [( Vec u )] r )
    : ( @ v ) c1 \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] rc ) ) ) }
    : ( @ v ) c2 \ → v {}
    : b k T
    ( run ? k c1 c2 )
    : C e @ C { ( mkread rd ) 3 }
    ( runc e )
    : ( Rc ( Vec u ) ) re ( rc_clone [( Vec u )] r )
    : C e2 ( mkhread re )
    ( runc e2 )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    // A Vec of closures that change the payload, run before the view is taken.
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } )
    ( runall fs )
    : ( Slice u ) sl2 ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( nurl_println_int # i ( slice_len [u] sl2 ) )
    ^ 0
}
