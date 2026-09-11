// diag_builtin_arg_type.nu — a float where a builtin's parameter is a
// pointer. This emitted `call void @nurl_print(double 1.5)` against
// `declare void @nurl_print(i8*)`: accepted by LLVM under opaque
// pointers, and the callee read whichever bytes the ABI left in the
// register. The same check an '&'-declared FFI symbol has always had.

@ main → i {
    ( nurl_print 1.5 )
    ^ 0
}
