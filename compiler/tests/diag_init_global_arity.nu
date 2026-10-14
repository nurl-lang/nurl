// diag_init_global_arity.nu — the function a global is set at start by
// must take no arguments and return the global's type; one that takes an
// argument is reported at the global.

$ `stdlib/std/thread.nu`

@ make i x → ( Locked i ) { ^ ( locked_new [i] x ) }

: ( Locked i ) g ( make )

@ main → i { ^ 0 }
