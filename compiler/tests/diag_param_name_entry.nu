// diag_param_name_entry.nu — 'entry' as a parameter name. It collides
// with the LLVM block label the function prologue emits, so the clash
// is real rather than stylistic.
@ f i entry → i { ^ entry }

@ main → i { ^ ( f 1 ) }
