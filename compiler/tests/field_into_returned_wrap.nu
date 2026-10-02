// field_into_returned_wrap.nu — a field of an owned local struct placed in
// a returned option / result leaves the struct's other fields to be dropped.
//
// `^ @ ?( Vec i ) { T . x a }`: the field moves out (emptied in `x`), but
// the returned literal counted `x` itself as the binding it returns, so `x`
// was not dropped at all and `x.b` leaked once per call (stdlib zstd's
// decoder handing its output buffer back). Binding the field first, or
// returning it bare, was clean.

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: S { ( Vec i ) a ( Vec i ) b }

@ mk → S {
    : S x @ S { ( vec_new [i] ) ( vec_new [i] ) }
    ( vec_push [i] . x a 1 )
    ( vec_push [i] . x b 2 )
    ^ x
}

@ in_option → ?( Vec i ) {
    : S x ( mk )
    ^ @ ?( Vec i ) { T . x a }
}

@ in_result → !( Vec i ) i {
    : S x ( mk )
    ^ @ !( Vec i ) i { T . x a }
}

@ main → i {
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        ?? ( in_option ) { T v → { = acc + acc ( vec_len [i] v ) } F → {} }
        ?? ( in_result ) { T v → { = acc + acc ( vec_len [i] v ) } F _ → {} }
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
