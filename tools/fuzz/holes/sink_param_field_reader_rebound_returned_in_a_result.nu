// sink_param_field_reader_rebound_returned_in_a_result: agora #268 — a binding read out of a `sink` parameter's field, re-bound and returned inside a result: the parameter dropped the field under the caller.
// Closed: a binding re-bound from one read out of a field (`: R a . col res  : R b a`, or `= b a`) reads that same field: handed on, it takes the field out of the struct as the first one would, instead of a cursor over a binding that owns nothing to hand over (__mem_udrop_bind_flag; agora #268).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #268: a sink parameter's field reader re-bound and returned inside a result (UAF)
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ answer sink C col → !R i {
    : R a . col res
    : R b a
    ^ @ !R i { T b }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C c @ C { @ R { xs } 0 }
    ?? ( answer c ) { T r → { ( nurl_println_int + 1 ( vec_at [i] . r v 0 ) ) } F _ → {} }
    ^ 0
}
