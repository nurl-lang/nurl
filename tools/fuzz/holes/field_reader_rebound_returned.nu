// field_reader_rebound_returned: agora #268 — a binding read out of a local struct's field, re-bound and returned (`^ b`): the struct dropped the field under the caller.
// Closed: a binding re-bound from one read out of a field (`: R a . col res  : R b a`, or `= b a`) reads that same field: handed on, it takes the field out of the struct as the first one would, instead of a cursor over a binding that owns nothing to hand over (__mem_udrop_bind_flag; agora #268).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #268: a field reader re-bound and returned (UAF)
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ answer i k → R {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs + 40 k )
    : C col @ C { @ R { xs } 0 }
    : R a . col res
    : R b a
    ^ b
}

@ main → i {
    : R r ( answer 1 )
    ( nurl_println_int + 1 ( vec_at [i] . r v 0 ) )
    ^ 0
}
