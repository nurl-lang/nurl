// diag_closures_a_holder_keeps_carry_what_they_do.nu — the closures a
// struct, an option or a Vec holds do what they do wherever the holder
// goes (Agora #736). Each closure below replaces an Rc's payload; a slice
// of that payload, taken through another handle, is read after the holder
// was handed to a function that runs what it holds, or after a closure
// read back out of it ran. A join of closures handed to a helper, and a
// maker's closure stored into a struct, are asked the same way (Agora
// #838), and so is a maker's closure over an rc_clone of its parameter
// (Agora #845), and a struct's closure field given a changing closure
// below its run in a loop, which the next round runs (Agora #843). Each
// function is refused, and so is handing the holder to a function that
// runs what it holds beside another handle on the Rc.
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ runo ? ( @ v ) o → v { ?? o { T g → { ( g ) } F → {} } }

@ runall ( Vec ( @ v ) ) fs → v { ?? ( vec_get [( @ v )] fs 0 ) { T g → { ( g ) } F → {} } }

@ run ( @ v ) f → v { ( f ) }

@ viewrun C c ( Rc ( Vec u ) ) other → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] other ) )
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    ^ \ → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) }
}

@ mkc ( Rc ( Vec u ) ) h → ( @ v ) {
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] h )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ one → ( Rc ( Vec u ) ) {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    ^ ( rc_new [( Vec u )] v0 )
}

// A struct's closure, run by a helper.
@ struct_run_by_a_helper → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// Read back out of the struct's field and run here.
@ read_out_and_run → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    : ( @ v ) g . c go
    ( g )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// Stored into the field after the struct was made.
@ stored_into_the_field → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ C c @ C { \ → v {} 1 }
    = . c go \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// An option of the closure.
@ option_run_by_a_helper → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ?( @ v ) o @ ?( @ v ) { T \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } }
    ( runo o )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A Vec of closures, the view taken after the push.
@ vec_run_by_a_helper → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runall fs )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A closure that hands a struct it captured to the helper.
@ run_by_a_closure → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    : ( @ v ) h \ → v { ( runc c ) }
    ( h )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A join of closures handed to a helper (Agora #838).
@ join_handed_to_a_helper → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : b k T
    : ( @ v ) c1 \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
    : ( @ v ) c2 \ → v {}
    ( run ? k c1 c2 )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A maker's closure stored in a struct, the view taken after the maker
// call (Agora #838).
@ maker_result_in_a_struct → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : C cc @ C { ( mk r ) 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runc cc )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A maker's closure over an rc_clone of its parameter, the view taken
// after the maker call (Agora #845).
@ maker_over_a_clone_run_after_the_view → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( @ v ) f ( mkc r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

// A struct's closure field given, below the helper's run in a loop, a
// closure that replaces the payload: the next round runs it (Agora #843).
@ given_below_its_run_in_a_loop → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ C c @ C { \ → v {} 1 }
    : ~ i k 0
    ~ < k 2 {
        ( runc c )
        ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
        = . c go \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
        = k + k 1
    }
}

// The struct handed beside another handle on the Rc its closure changes,
// to a function that runs the struct's closure through a helper.
@ handed_beside_another_handle → v {
    : ( Rc ( Vec u ) ) r ( one )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    ( viewrun c r2 )
}

@ main → i {
    ^ 0
}
