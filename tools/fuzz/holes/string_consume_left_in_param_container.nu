// string_consume_left_in_param_container: a `sink s` parameter pushed into a container the caller holds: nobody releases the string.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// `add` takes `x` as `sink s` and pushes it into the caller's ( Vec s ); a Vec of raw strings holds views
// and owns nothing, so the string main gave up is released by neither the callee nor the Vec. A fix
// that releases a `sink s` when its callee returns must not do it here: the Vec still points at it.
// LSan: detected memory leaks — 6 bytes (the "abcde" buffer from nurl_str_cat).
// map: §2.13 | A2 | rejected | h164 | sink s param pushed into caller's Vec s; nobody frees it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add ( Vec s ) v sink s x → v { ( vec_push [s] v x ) }

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( add v ( nurl_str_cat `ab` `cde` ) )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ^ 0
}
