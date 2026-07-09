// should_fail_call_arg_scalar_for_ptr.nu — the reverse of
// should_fail_call_arg_ptr_for_scalar: a bare scalar (`42`, i64) passed
// where a pointer parameter (`s`, i8*) is expected. The parameter's
// pointer-ness has no literal `*`, so this only fires because the guard
// detects pointer-ness from the lowered type.

@ shout s m → v { ( nurl_print m ) }

@ main → i {
    ( shout 42 )
    ^ 0
}
