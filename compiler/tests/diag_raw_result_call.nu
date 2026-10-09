// diag_raw_result_call.nu — a call that hands back a raw pointer is raw
// memory: only an `unsafe` function may take what it returns.
//
// `vec_data` hands back a Vec's buffer as a `*A`. Safe code could not read
// through it, but it could pass it on where a string is expected —
// `( nurl_println ( vec_data v ) )` read to a NUL the bytes do not have
// (hole probe h98) — bind it, return it, or keep it past the Vec. The call
// itself is where the line is drawn, as for a call that takes a raw
// pointer. The control: the same call inside an `unsafe` function, whose
// author vouches for what is done with the address, compiles.

$ `stdlib/core/vec.nu`

unsafe @ first_byte ( Vec u ) v → i {
    : *u p ( vec_data [u] v )
    ^ # i . p 0
}

@ show ( Vec u ) v → v {
    ( nurl_println ( vec_data [u] v ) )
}

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 65 )
    ( nurl_println_int ( first_byte v ) )
    ( show v )
    ^ 0
}
