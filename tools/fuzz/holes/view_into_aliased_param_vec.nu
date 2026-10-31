// view_into_aliased_param_vec: a view of a local stored through a Vec binding that aliases a parameter: the caller reads freed memory.
// Closed: storage the caller holds (a parameter, an alias of one, an `inout` struct) may not keep a view of a binding released here (bck_param_view_check, bck_caller_view_diag); a field store records the view (gen_field_rhs).
// `addl` binds `w` to its parameter `v` (the caller's Vec) and pushes `x`, a fresh string it releases
// when it returns. A ( Vec s ) holds views; the push of a local's view through the alias is not reported
// (nor is the direct push, view_into_param_container), and main reads element 0 after `x` was released.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading element 0.
// map: FnOK | A1 | rejected | h171 | view of local pushed via alias of caller's Vec param; caller reads
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ addl ( Vec s ) v → v { : s x ( nurl_str_cat `ab` `cd` ) : ( Vec s ) w v ( vec_push [s] w x ) }

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( addl v )
    ?? ( vec_get [s] v 0 ) { T e → ( nurl_println e ) F → {} }
    ( nurl_println `P50D-MARK` )
    ^ 0
}
