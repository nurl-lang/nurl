// diag_stale_borrow_kept_forward.nu — a view handed to a callee that may
// KEEP it in a container stops depending on definition order.
//
// In raw code, `( f c ( string_data x ) )` makes the container `c` hold a
// view of `x` when `f` keeps that argument; mutating `x` afterwards makes
// `c` stale. For a callee already compiled the compiler knows whether it
// keeps the argument. For one not compiled yet it assumed it did — and
// the stale report then printed at once, even when the callee, compiled
// further down, only copied the string: the same program rejected or
// accepted depending on where the author put the function.
//
// The borrow is now recorded as conditional on the callee keeping that
// argument, a later mutation of the view's source turns the condition
// into the dead mark (`k:<callee>`), and resolve_pending_stale() decides
// after the module with the callee's final summary.
//
// Two positives (the forward callee keeps the view, at the top level and
// inside a `?` arm) and two controls (a forward callee that copies the
// view instead, and the same with the callee above).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ count ( Vec s ) t → i { ^ ( vec_len [s] t ) }

@ count_owned ( Vec String ) t → i { ^ ( vec_len [String] t ) }

// POSITIVE — `keep_view` (bottom of the file) pushes the view into `t`.
unsafe @ stale_kept_forward s body → i {
    : ~ String src ( string_from body )
    : ~ ( Vec s ) views ( vec_new [s] )
    : s _r ( keep_view views ( string_data src ) )
    ( string_push_str src `y` )
    ^ ( count views )  // error
}

// POSITIVE — the mutation inside a `?` arm.
unsafe @ stale_kept_forward_in_arm s body i flag → i {
    : ~ String src ( string_from body )
    : ~ ( Vec s ) views ( vec_new [s] )
    : s _r ( keep_view views ( string_data src ) )
    ? > flag 0 { ( string_push_str src `y` ) } {}
    ^ ( count views )  // error
}

// CONTROL — `copy_view` (bottom of the file) stores a copy, so `names`
// holds nothing of `src`.
unsafe @ no_error_copied_forward s body → i {
    : ~ String src ( string_from body )
    : ~ ( Vec String ) names ( vec_new [String] )
    : s _r ( copy_view names ( string_data src ) )
    ( string_push_str src `y` )
    ^ ( count_owned names )
}

@ copy_above inout ( Vec String ) t s v → s {
    ( vec_push [String] t ( string_from v ) )
    ^ ``
}

// CONTROL — the same with the callee above: it always passed.
unsafe @ no_error_copied_above s body → i {
    : ~ String src ( string_from body )
    : ~ ( Vec String ) names ( vec_new [String] )
    : s _r ( copy_above names ( string_data src ) )
    ( string_push_str src `y` )
    ^ ( count_owned names )
}

@ keep_view inout ( Vec s ) t s v → s {
    ( vec_push [s] t v )
    ^ ``
}

@ copy_view inout ( Vec String ) t s v → s {
    ( vec_push [String] t ( string_from v ) )
    ^ ``
}

@ main → i { ^ 0 }
