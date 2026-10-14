// diag_init_global_not_sync.nu — a global set at start (`: T g ( make )`)
// is read by every thread without a lock, so its type must synchronise
// itself; an `i` set that way is rejected.

@ make → i { ^ 1 }

: i g ( make )

@ main → i { ^ g }
