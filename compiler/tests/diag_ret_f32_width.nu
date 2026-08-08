// diag_ret_f32_width.nu — returning an f32 from a '→ f' function.
// The integer-width return contract already rejected `ret i1` out of an
// i64 function; the float dual (`ret float` out of a `define double`)
// still slid through as invalid IR only the LLVM verifier caught, three
// build stages later.
@ get f32 x → f { ^ x }

@ main → i {
    : f z ( get 1.5 )
    ^ 0
}
