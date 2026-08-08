// diag_call_int_to_float_param.nu — the mirror image of the
// float→int case: an integer argument to a float parameter. Same
// silent-miscompile shape (`call double @half(i64 …)`), same law: the
// binding check already rejects ': f z 3', so the call boundary must too.
@ half f x → f { ^ / x 2.0 }

@ main → i {
    : i y 3
    : f z ( half y )
    ^ 0
}
