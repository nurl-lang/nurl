// should_fail_cast_aggregate.nu — `#` must reject an aggregate operand.
//
// `vec_get` hands back `?u`, not `u`. Casting that option straight to an
// integer used to slip through gen_cast's final no-op branch: the
// aggregate register was passed on wearing the target's type, and the
// only thing that noticed was the LLVM verifier, one stage later, with a
// message about SSA registers rather than about the source. The cast is
// a type error and must be reported as one.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    : i n # i ( vec_get [u] v 0 )
    ( vec_free [u] v )
    ^ n
}
