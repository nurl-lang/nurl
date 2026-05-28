// sink_basic.nu — the `sink` parameter convention.
//
// A `sink` parameter consumes (takes ownership of) its
// argument — the callee owns the value and is responsible for it,
// and the caller may not use the argument binding afterwards.
//
// `sink` lowers to an ordinary by-value parameter; the convention is
// enforced by the borrow checker (the argument binding is recorded
// as moved). Here `sum_and_free` consumes a Vec, sums it, and frees
// it — `main` hands the Vec off and never touches it again.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

// Consumes the Vec: sums its elements, then frees it.
@ sum_and_free sink ( Vec i ) g → i {
    : ~ i total 0
    : i n ( vec_len [i] g )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] g k ) {
            T e → { = total + total e }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [i] g )
    ^ total
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 10 )
    ( vec_push [i] xs 20 )
    ( vec_push [i] xs 12 )
    : i s ( sum_and_free xs )      // xs is consumed here
    ( nurl_print `sum=` ) ( nurl_print ( nurl_str_int s ) ) ( nurl_print `\n` )
    ^ 0
}
