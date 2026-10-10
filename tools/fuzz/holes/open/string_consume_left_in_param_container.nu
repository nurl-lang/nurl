// OPEN in 0.72.0 — a `sink s` parameter pushed into a container the caller holds: nobody releases the string.
// `add` takes `x` as `sink s` and pushes it into the caller's ( Vec s ); a Vec of raw strings holds views
// and owns nothing, so the string main gave up is released by neither the callee nor the Vec. A fix
// that releases a `sink s` when its callee returns must not do it here: the Vec still points at it.
// LSan: detected memory leaks — 6 bytes (the "abcde" buffer from nurl_str_cat).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add ( Vec s ) v sink s x → v { ( vec_push [s] v x ) }

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( add v ( nurl_str_cat `ab` `cde` ) )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ^ 0
}
