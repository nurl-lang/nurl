// sink_param_field_returned_in_a_struct_literal: agora #257 — a field of a `sink` struct parameter returned as a field of a struct literal: the caller read it freed.
// Closed: a `sink` parameter is a struct this function owns and drops, as a binding of its own: a field read out of it moves out where it is handed on — zeroed in the parameter and owned by the result (__fn_owns_struct; agora #257).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #257: a sink parameter's field returned inside a struct literal (UAF)
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

: D { R r i n }

@ answer sink C col → D {
    ^ @ D { . col res 1 }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C c @ C { @ R { xs } 0 }
    : D d ( answer c )
    ( nurl_println_int + 1 ( vec_at [i] . . d r v 0 ) )
    ^ 0
}
