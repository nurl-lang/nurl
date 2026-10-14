// diag_init_global_args.nu — a global set at start is initialised by a
// function of NO arguments; a call with arguments is rejected with the
// advice to wrap it.

$ `stdlib/std/thread.nu`

@ make i x → ( Locked i ) { ^ ( locked_new [i] x ) }

: ( Locked i ) g ( make 5 )

@ main → i { ^ 0 }
