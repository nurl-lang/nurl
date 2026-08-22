// diag_param_name_reg.nu — a parameter named `r` + digits. A by-value
// parameter keeps its source name as its LLVM SSA register, and the code
// generator's temporaries are %r0, %r1, … in the same namespace, so the
// two collide. nurlc used to emit the clashing IR and exit 0; clang then
// reported "multiple definition of local value named 'r0'" against a file
// the user never wrote.
@ f i r0 → i { ^ + r0 1 }

@ main → i { ^ ( f 41 ) }
