// sink_param_field_returned_in_an_option: agora #257 — a field of a `sink` struct parameter, bound and returned inside an option: the caller read it freed.
// Closed: a `sink` parameter is a struct this function owns and drops, as a binding of its own: a field read out of it moves out where it is handed on — zeroed in the parameter and owned by the result (__fn_owns_struct; agora #257).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #257: a sink parameter's field bound and returned inside an option (UAF)
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ answer sink C col → ?R {
    : R res . col res
    ^ @ ?R { T res }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C c @ C { @ R { xs } 0 }
    ?? ( answer c ) { T r → { ( nurl_println_int + 1 ( vec_at [i] . r v 0 ) ) } F → {} }
    ^ 0
}
