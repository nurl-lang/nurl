// An immutable global of a type whose zero bytes are not a value of it
// (a Vec, a String, a library handle, a closure, or what holds one) would
// be a null handle for the whole run: read, it is empty, and a change
// through it writes through null (AGORA-987). Refused at the declaration.
$ `stdlib/core/vec.nu`

: ( Vec i ) g_v 0

@ add i x → v { ( vec_push [i] g_v x ) }

@ main → i {
    ( add 7 )
    ( nurl_println_int ( vec_len [i] g_v ) )
    ^ 0
}
