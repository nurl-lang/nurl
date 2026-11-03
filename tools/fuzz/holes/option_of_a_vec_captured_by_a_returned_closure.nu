// option_of_a_vec_captured_by_a_returned_closure: agora #458 — a local `?( Vec i )` captured by a returned closure, called twice
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a local `?( Vec i )` captured by a returned closure, called twice
$ `stdlib/core/vec.nu`

@ mk → ?( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 41 ) ( vec_push [i] v 1 )
    ^ @ ?( Vec i ) { T v }
}

@ cap → ( @ i ) {
    : ?( Vec i ) x ( mk )
    ^ \ → i { ?? x { T v → { ^ ( vec_len [i] v ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
