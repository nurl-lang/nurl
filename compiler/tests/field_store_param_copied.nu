// field_store_param_copied.nu — a parameter the function only borrows,
// stored into a field of a struct of its own, is copied.
//
// `@ g ( Vec u ) v → i { : ~ A a … = . a f v … }`: the store took `v`'s
// handle and the call was taken to KEEP the argument (as vec_push keeps
// its element), so the caller handed `d` over — and `a`, a local, freed it
// when g returned, while the caller went on reading `d` (stdlib TLS
// record-layer helpers). The literal `@ A { v 0 }` copies a borrowed
// parameter; the field store now does the same. A `sink` parameter is the
// function's own and moves in.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: AImpl { ( Vec u ) f i n }

@ g ( Vec u ) v → i {
    : ~ AImpl a @ AImpl { ( vec_new [u] ) 0 }
    = . a f v
    ^ ( vec_len [u] . a f )
}

@ g_sink sink ( Vec u ) v → i {
    : ~ AImpl a @ AImpl { ( vec_new [u] ) 0 }
    = . a f v
    ^ ( vec_len [u] . a f )
}

@ main → i {
    : i l0 ( live )
    : ( Vec u ) d ( bytes_from_str `hello` )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        = acc + acc ( g d )
        = acc + acc ( vec_len [u] d )
        = acc + acc ( g_sink ( bytes_from_str `abc` ) )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    // d remains: its Vec (ctl + buffer)
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
