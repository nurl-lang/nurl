// diag_duplicate_param_name.nu — two parameters with the same name used
// to lower to `define i64 @f(i64 %a, i64 %a)`. LLVM requires distinct
// argument names, so clang rejected the module with "redefinition of
// argument '%a'" — a line number into generated IR, no NURL source
// location, and nothing to say which declaration was wrong. The body
// meanwhile could only reach one of the two.

@ f i a i a → i { ^ a }

@ main → i {
    ^ ( f 1 2 )
}
