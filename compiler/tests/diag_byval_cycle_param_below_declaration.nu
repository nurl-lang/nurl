// diag_byval_cycle_param_below_declaration.nu — the same cycle declared
// first: the diagnostic was printed, then nurlc crashed.

: A { i n B b }
: B { i m A a }

@ use A a → i { ^ 0 }

@ main → i { ^ 0 }
