// The handle-wrapper cast round trip: a type whose FIRST FIELD is a
// pointer (a Vec, a String, any single-pointer handle) can be taken
// apart to a raw `s` and rebuilt with `# T ptr` — the inverse of
// reading the handle out, and the shape stdlib code uses to park a
// Vec handle in a `( Vec s )` slot. gen_cast lowers it as a bitcast
// into field 0; before that branch existed the cast compiled and then
// failed in clang as invalid IR (`ptr but expected %Vec__u8`).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box { s raw }

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    ( vec_push [u] v # u 40 )
    // park the handle as a raw pointer, the way a ( Vec s ) slot would
    : s parked # s v
    // …and rebuild the handle from it
    : ( Vec u ) back # ( Vec u ) parked
    : i a ?? ( vec_get [u] back 0 ) { T x → # i x F → 0 }
    : i b ?? ( vec_get [u] back 1 ) { T x → # i x F → 0 }
    ( nurl_print `sum=` )
    ( nurl_print ( nurl_str_int + a b ) )
    ( nurl_print `\n` )
    ( vec_free [u] v )
    ^ 0
}
