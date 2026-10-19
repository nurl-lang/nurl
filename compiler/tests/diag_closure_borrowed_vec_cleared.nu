// diag_closure_borrowed_vec_cleared.nu — a closure lent out of a Vec (a
// vec_get payload) borrows from the Vec: clearing it drops the env, and
// calling the payload after it is rejected.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
// A closure lent out of a Vec (vec_get's payload), the Vec cleared under it, then called: must be rejected.
@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs \ i x → i { ^ + x ( string_len a ) } )
    ?? ( vec_get [( @ i i )] fs 0 ) { T g → { ( vec_clear [( @ i i )] fs ) ( nurl_println_int ( g 1 ) ) } F → {} }
    ^ 0
}
