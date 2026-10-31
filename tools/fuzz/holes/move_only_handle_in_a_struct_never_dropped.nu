// move_only_handle_in_a_struct_never_dropped: a struct holding a library handle that cannot be copied — no share or clone hook, like a lock guard (WGuard), or a clone that cannot copy what it holds — was dropped by nobody. It was not an owning struct (a field it cannot copy), and the field-by-field drop the compiler writes for a struct that cannot be copied was keyed on a field with a `% Drop` of the program's own. The guard's drop never ran: its lock stayed held (the next writer waited forever) and its share of the lock leaked.
// Closed: a library handle that cannot be copied is a field the struct is dropped field by field for, in an option or a container too (__is_moveonly_libh in __needs_synth_drop / __holds_user_drop).
// main (before this PR): LeakSanitizer: the guard's block leaked; with a second rw_write the program hung.
// map: §7.6 | A2 | runs-clean | h290 | struct holding a lock guard (no share/clone hook) was dropped by nobody: lock held, block leaked
$ `stdlib/core/vec.nu`
$ `stdlib/std/rwlock.nu`

: Fr { i pid }
: Held { i n ( WGuard Fr ) g }
: MaybeHeld { i n ? ( WGuard Fr ) g }

@ hold ( RwLocked Fr ) l → v { : Held h @ Held { 1 ( rw_write [Fr] l ) } }

@ maybe_hold ( RwLocked Fr ) l → v { : MaybeHeld h @ MaybeHeld { 1 @ ?( WGuard Fr ) { T ( rw_write [Fr] l ) } } }

@ main → i {
    : ( RwLocked Fr ) l ( rw_new [Fr] @ Fr { 0 } )
    ( hold l )
    ( maybe_hold l )
    : ( WGuard Fr ) g ( rw_write [Fr] l )
    ( nurl_println `the lock was free` )
    ^ 0
}
