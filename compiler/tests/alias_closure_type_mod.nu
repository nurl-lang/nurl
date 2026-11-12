// fixture: module; alias_closure_type_mod.nu — helper module for
// alias_closure_type.nu: top-level functions whose parameters and results
// are closure TYPES. The `@` inside `( @ v )` / `( @ i i )` is part of a
// type, not a declaration.

@ apply_twice ( @ i i ) f i x → i { ^ ( f ( f x ) ) }

@ run_it ( @ v ) body → v { ( body ) }

@ adder i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

: i BASE 40
