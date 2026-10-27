// mem_dup_of_a_lend_is_owned.nu — `( mem_dup ( f … ) )` over a call that
// lends is a value of its own: no view of what the call lent. A copy of an
// Arc's payload may be changed (the payload is frozen, the copy is not) and
// outlives the Arc; a copy of a vec_at element outlives the vector. The
// borrow walk took the line's lending call for the binding's own, and the
// copy was rejected as a change to the payload.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Holder { i id ( Vec ( Arc i ) ) kids }

@ main → i {
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] ( vec_new [i] ) )
    : ( Vec i ) v ( mem_dup ( arc_get [( Vec i )] a ) )
    ( vec_push [i] v 1 )
    ( arc_free [( Vec i )] a )
    : ( Arc Holder ) h ( arc_new [Holder] @ Holder { 1 ( vec_new [( Arc i )] ) } )
    : Holder c ( mem_dup ( arc_get [Holder] h ) )
    ( vec_push [( Arc i )] . c kids ( arc_new [i] 5 ) )
    ( vec_push [( Arc i )] . c kids ( arc_new [i] 6 ) )
    : ( Vec ( Vec i ) ) vs ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vs ( vec_new [i] ) )
    : ( Vec i ) e ( mem_dup ( vec_at [( Vec i )] vs 0 ) )
    ( vec_free [( Vec i )] vs )
    ( vec_push [i] e 7 )
    ( nurl_print_int ( vec_len [i] v ) ) ( nurl_print `\n` )
    ( nurl_print_int ( vec_len [( Arc i )] . c kids ) ) ( nurl_print `\n` )
    ( nurl_print_int ( vec_len [( Arc i )] . ( arc_get [Holder] h ) kids ) ) ( nurl_print `\n` )
    ( nurl_print_int ( vec_len [i] e ) ) ( nurl_print `\n` )
    ^ 0
}
