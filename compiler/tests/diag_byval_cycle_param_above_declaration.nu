// diag_byval_cycle_param_above_declaration.nu — two structs that hold
// each other by value, used as a parameter above their declarations:
// refused as having no finite size. nurlc crashed (__type_needs_drop went
// round the cycle until the stack ran out), on main before #772 too.

@ use A a → i { ^ 0 }

: A { i n B b }
: B { i m A a }

@ main → i { ^ 0 }
