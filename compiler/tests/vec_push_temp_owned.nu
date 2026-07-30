// Regression: an owned-string TEMPORARY passed to `vec_push [s]` must
// NOT be auto-freed after the call — the container now owns it. The old
// arg-temp protocol freed every owned temp regardless of the consumer,
// so the vector held freed memory and reading the element back was
// use-after-free (masked in production by the small-alloc cache keeping
// the bytes intact until reuse). gen_call's collect gate now frees a
// temp only for consumers that provably neither keep the pointer nor
// return an alias of it.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    : ~ i k 0
    ~ < k 5 {
        ( vec_push [s] v ( nurl_str_cat `item` ( nurl_str_int k ) ) )
        = k + k 1
    }
    : ~ i acc 0
    ?? ( vec_get [s] v 3 ) {
        T got → { = acc ( nurl_str_len got ) ( puts got ) }
        F → { = acc -1 }
    }
    ^ ? == acc 5 0 1
}
