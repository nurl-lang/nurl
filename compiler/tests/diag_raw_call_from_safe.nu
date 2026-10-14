// diag_raw_call_from_safe.nu — a `raw @` function (grammar v2.9) trusts its
// caller for what it requires, so only an `unsafe` function may call it:
// here safe code hands it a count past the Vec, which it reads through a
// raw pointer.
$ `stdlib/core/vec.nu`

// requires: n <= vec_len v
raw @ sum_first ( Vec i ) v i n → i {
    : *i p ( vec_data [i] v )
    : ~ i s 0
    : ~ i k 0
    ~ < k n { = s + s . p k = k + k 1 }
    ^ s
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ^ ( sum_first v 1000 )
}
