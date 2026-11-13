// vec_of_closures_element_run_beside_a_view_taken_after_the_push_is_refused: a closure capturing an Rc pushed into a Vec; a slice taken through another handle after the push; the element read out with vec_get and run here; the slice is read after
// Closed: agora #736, the Vec handed to vec_get may run what it holds there.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a Vec's closure read out and run replaces an Rc's payload beside a view taken after the push
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ?? ( vec_get [( @ v )] fs 0 ) { T g → { ( g ) } F → {} }
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
