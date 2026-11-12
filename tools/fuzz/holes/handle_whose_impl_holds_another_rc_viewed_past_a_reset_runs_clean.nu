// handle_whose_impl_holds_another_rc_viewed_past_a_reset_runs_clean: `Doc { ( Rc DocImpl ) h }` with the impl holding a shared undo log, a view of the impl's own field kept past a change of the log's payload (the shape the fix must keep)
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage (agora #726).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: a handle whose impl holds another Rc, viewed past a reset of that Rc
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: DocImpl { ( Vec u ) text ( Rc ( Vec i ) ) undo }
: Doc { ( Rc DocImpl ) h }

@ doc_new ( Rc ( Vec i ) ) undo → Doc {
    : ~ ( Vec u ) t ( vec_new [u] )
    ( vec_push [u] t 104 )
    ^ @ Doc { ( rc_new [DocImpl] @ DocImpl { t ( rc_clone [( Vec i )] undo ) } ) }
}

@ log_op ( Rc ( Vec i ) ) l i op → v { ( vec_push [i] ( rc_get [( Vec i )] l ) op ) }

@ main → i {
    : ( Rc ( Vec i ) ) undo ( rc_new [( Vec i )] ( vec_new [i] ) )
    : Doc d ( doc_new undo )
    : ( Slice u ) tx ( slice_from_vec [u] . ( rc_get [DocImpl] . d h ) text )
    ( log_op undo 1 )
    ( nurl_println_int + # i ( slice_at [u] tx 0 ) ( vec_len [i] ( rc_get [( Vec i )] undo ) ) )
    ^ 0
}
