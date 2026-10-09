// diag_temp_lend_nocopy.nu — a part of a temporary that cannot be copied
// cannot be borrowed past the call that made it.
//
// `( vec_get [DH] ( mk ) 1 )`: the element lives inside the temporary Vec,
// and a `% Drop` struct with no clone cannot be copied out of it (a
// String element is: temp_container_lend.nu). The temporary could then be
// dropped neither after the call — the result points into it — nor after
// the result's last use, which no binding tracks; it leaked, with the
// element freed through the result while the Vec still held it. An error
// with the fix: bind the container to a name, which lives to the end of
// its scope (the control at the bottom compiles).

$ `stdlib/core/vec.nu`

: ~ i g_drops 0

: DH { * u buf i id }

% Drop ( DH ) { unsafe @ drop DH h → v { = g_drops + g_drops 1 ( nurl_free # s . h buf ) } }

unsafe @ mkd i id → DH { ^ @ DH { # *u ( malloc 16 ) id } }

@ mk → ( Vec DH ) {
    : ( Vec DH ) v ( vec_new [DH] )
    ( vec_push [DH] v ( mkd 1 ) )
    ( vec_push [DH] v ( mkd 2 ) )
    ^ v
}

@ main → i {
    ?? ( vec_get [DH] ( mk ) 1 ) { T e → { ( nurl_println_int . e id ) } F → {} }
    : ?DH o ( vec_get [DH] ( mk ) 0 )
    ?? o { T e → { ( nurl_println_int . e id ) } F → {} }
    // Control: the container is a binding.
    : ( Vec DH ) v ( mk )
    ?? ( vec_get [DH] v 1 ) { T e → { ( nurl_println_int . e id ) } F → {} }
    ^ 0
}
