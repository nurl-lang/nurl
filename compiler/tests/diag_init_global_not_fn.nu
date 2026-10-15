// diag_init_global_not_fn.nu — a global set at start names a function
// (`: ( Locked T ) g ( make_state )`); a literal there is rejected.

$ `stdlib/std/thread.nu`

: ( Locked i ) g ( 5 )

@ main → i { ^ 0 }
