// diag_ret_struct_and_generic_arity.nu — two shapes that reached past
// nurlc, both found by tools/metamorph's invalid-input class.
//
// 1. RETURNING A HANDLE WHERE A NUMBER IS DECLARED. `^ ( vec_new [i] )`
//    from a `→ i` function lowered `ret %Vec__i64 %r1` out of a
//    `define i64`, so nurlc exited 0 and the LLVM verifier reported
//    "value doesn't match function result type" against generated IR.
//    The return-type chain asked about every pair of shapes it knew —
//    float/float, int/int, `{…}`/`{…}`, struct/struct, int/enum — and a
//    struct beside a plain number matched none of them, so it fell
//    through to the emit.
//
// 2. A GENERIC CALLED WITH THE WRONG NUMBER OF ARGUMENTS. The call-site
//    arity check was conditioned on `call_name == fname`, which is false
//    for a generic (call_name is the mangled name), and generics
//    recorded no parameter count anyway. `( vec_push [i] v )` — one
//    argument short — was accepted. A missing argument reads an unset
//    ABI register, which is the same silent failure the FFI arity check
//    exists to prevent.
//
//    The count is recorded under `__garity`, not `__arity`: a file may
//    define its own non-generic function with the same name as an
//    imported generic (compiler/tests/ws_permessage_deflate.nu has a
//    2-parameter `vec_eq` beside the stdlib's 3-parameter generic one),
//    and writing the template's count into the shared key made every
//    call to the LOCAL function look one argument short. That false
//    positive is why the two keys are separate.
//
// Two functions, because recovery is per declaration: one error each.

$ `stdlib/core/vec.nu`

@ returns_a_handle_as_a_number → i {
    ^ ( vec_new [i] )
}

@ generic_missing_an_argument → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v )
    ^ 0
}

@ main → i {
    : i a ( returns_a_handle_as_a_number )
    : i b ( generic_missing_an_argument )
    ^ + a b
}
