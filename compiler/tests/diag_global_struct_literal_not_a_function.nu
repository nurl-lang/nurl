// diag_global_struct_literal_not_a_function.nu — a global whose value is
// a struct literal, `: S g @ S { … }`, is refused for what it is (a global
// takes a literal constant). The `@ S {` is no function `@ S`, so it does
// not clash with the type `S` (agora #728's one-namespace check).

: S { i a i b }

: S g

@ S { 4 5 }

@ main → i { ^ - . g a 4 }
