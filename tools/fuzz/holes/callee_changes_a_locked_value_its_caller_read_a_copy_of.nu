// callee_changes_a_locked_value_its_caller_read_a_copy_of: agora #315 — a callee clearing a lock's value through its write guard (`: ( Vec String ) v ( wguard_get g )`, `( vec_clear v )`); the caller read a copy of it (rw_get) before the call (the shape the fix must keep).
// Closed: a handle read past a shared cell's accessor (arc_get, rw_read, rw_write, rguard_get, wguard_get) is no parameter's storage to the summaries — an Arc's payload is frozen, and a lock's value is reached only through a guard the lock makes exclusive at run time (__shared_cell_get; agora #315).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #315: a callee clearing a locked value through its guard
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rwlock.nu`

@ clear_locked ( RwLocked ( Vec String ) ) l → v {
    : ( WGuard ( Vec String ) ) g ( rw_write [( Vec String )] l )
    : ( Vec String ) v ( wguard_get [( Vec String )] g )
    ( vec_clear [String] v )
}

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ( RwLocked ( Vec String ) ) l ( rw_new [( Vec String )] inner )
    : String s0 ( vec_at [String] ( rw_get [( Vec String )] l ) 0 )
    ( clear_locked l )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
