// diag_ret_closure_uncalled.nu — a closure-typed value returned where
// the function declares the closure's own RESULT type. The shape is
// almost always a call that lost its parens ('^ f( r )' — the C-style
// call typo names the closure and strands the argument), and it used
// to emit `ret { i64 (i8*, i64)*, i8* } %f` out of an i64 function:
// invalid IR only the LLVM verifier saw, three build stages later,
// with a .ll line number and no source location. The total-agreement
// backstop in ret_ty_agree now rejects it at the source line, with
// the parenthesised-prefix cure spelled out.

@ run ( @ i i ) f i r → i {
    ^ f ( r )
}

@ main → i {
    : ( @ i i ) cl \ i x → i { ^ * x 2 }
    ( nurl_print_int ( run cl 5 ) )
    ^ 0
}
