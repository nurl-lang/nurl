// H187: `: ( Vec i ) v 0` turned the number into the Vec's control block address — a Vec with no control block — and vec_push wrote through null. `= v 0`, `: String s 0` and an integer for a Vec field of a struct literal did the same.
// Closed: outside `unsafe` a number never becomes a String, a Vec or a library handle (coerce_store_val, gen_agg_lit).
// ASan: SEGV in vec_push (main).
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v 0
    ( vec_push [i] v 1 )
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}
