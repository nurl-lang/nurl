// vec_of_closures_handed_to_a_function_looping_over_it_beside_another_handle_is_refused: a Vec of closures, one replacing an Rc's payload, handed beside another handle on that Rc to a function that views through the handle and runs every element in a `~` loop
// Closed: agora #736, an element of a holder parameter is one of what it holds.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a Vec of closures handed beside another handle on the Rc one changes, run in a loop over it
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ viewrun ( Vec ( @ v ) ) fs ( Rc ( Vec u ) ) rb → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    ~ g fs { ( g ) }
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
