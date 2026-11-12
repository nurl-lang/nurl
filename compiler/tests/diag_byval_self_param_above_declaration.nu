// diag_byval_self_param_above_declaration.nu — a struct that holds itself
// by value, used as a parameter above its declaration: refused, no crash.

@ use A a → i { ^ 0 }

: A { i n A b }

@ main → i { ^ 0 }
