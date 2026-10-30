// zeroed_vec_of_vecs: `vec_zeroed [( Vec i )] 2` made two elements of zero bytes — Vecs with no control block — and vec_push on one wrote through null. `box_zero`, `rc_zero`, `arc_zero` and `vec_resize_zeroed` did the same for their values.
// Closed: outside `unsafe` the zero-filling constructors take only a type a zero is a value of (gen_call, __zero_invalid).
// ASan: SEGV in vec_push (main).
// map: §6.2 | B | rejected | h186 | vec_zeroed of Vec elements makes Vecs with no control block
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_zeroed [( Vec i )] 2 )
    ?? ( vec_get [( Vec i )] vv 0 ) {
        T v → {
            ( vec_push [i] v 1 )
            ( nurl_println_int ( vec_len [i] v ) )
        }
        F → {}
    }
    ^ 0
}
