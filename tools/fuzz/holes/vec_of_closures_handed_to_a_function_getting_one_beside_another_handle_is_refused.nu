// vec_of_closures_handed_to_a_function_getting_one_beside_another_handle_is_refused: the same, the function reading an element out with vec_get and running it
// Closed: agora #736, a call's result is one of what its holder arguments hold.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a Vec of closures handed beside another handle, an element read out with vec_get and run
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ viewrun ( Vec ( @ v ) ) fs ( Rc ( Vec u ) ) rb → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    ?? ( vec_get [( @ v )] fs 0 ) { T g → { ( g ) } F → {} }
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } )
    ( viewrun fs r2 )
    ^ 0
}
