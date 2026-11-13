// option_of_a_closure_handed_beside_another_handle_on_the_rc_it_changes_is_refused: an option of a closure that replaces an Rc's payload, handed beside another handle on that Rc to a function that views through the handle, matches the option and runs its payload
// Closed: agora #736, a payload of a holder parameter is one of what it holds.
// main e294ee30: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: an option of a closure handed beside another handle on the Rc it changes
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ viewrun ? ( @ v ) o ( Rc ( Vec u ) ) rb → v {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    ?? o { T g → { ( g ) } F → {} }
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ?( @ v ) o @ ?( @ v ) { T \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } }
    ( viewrun o r2 )
    ^ 0
}
