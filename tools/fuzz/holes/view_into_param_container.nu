// view_into_param_container: a view of a local string pushed into a container the caller holds: the caller reads freed memory.
// Closed: storage the caller holds (a parameter, an alias of one, an `inout` struct) may not keep a view of a binding released here (bck_param_view_check, bck_caller_view_diag); a field store records the view (gen_field_rhs).
// `add` pushes `x`, a fresh string it owns, into the caller's ( Vec s ) — which holds views — and releases
// `x` when it returns; main then reads element 0 through the Vec.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading element 0.
// map: FnOK | A1 | rejected | h173 | view of local pushed into caller's Vec s param; local freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add ( Vec s ) v → v {
    : s x ( nurl_str_cat `ab` `cde` )
    ( vec_push [s] v x )
}

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( add v )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ^ 0
}
