// field_reader_rebound_vec_returned_in_an_option: agora #268 — a Vec read out of a local struct's field, re-bound and returned inside an option: the struct dropped it under the caller.
// Closed: a binding re-bound from one read out of a field (`: R a . col res  : R b a`, or `= b a`) reads that same field: handed on, it takes the field out of the struct as the first one would, instead of a cursor over a binding that owns nothing to hand over (__mem_udrop_bind_flag; agora #268).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #268: a Vec field reader re-bound and returned inside an option (UAF)
$ `stdlib/core/vec.nu`

: C { ( Vec i ) v i rc }

@ answer i k → ?( Vec i ) {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs + 40 k )
    : C col @ C { xs 0 }
    : ( Vec i ) a . col v
    : ( Vec i ) b a
    ^ @ ?( Vec i ) { T b }
}

@ main → i {
    ?? ( answer 1 ) { T r → { ( nurl_println_int + 1 ( vec_at [i] r 0 ) ) } F → {} }
    ^ 0
}
