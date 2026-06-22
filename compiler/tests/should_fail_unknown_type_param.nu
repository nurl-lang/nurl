// should_fail_unknown_type_param.nu — a function parameter of an undeclared
// type. Caught at the source instead of emitting an undefined `%Zorp`.
@ f Zorp x → i { ^ 0 }

@ main → i { ^ 0 }
