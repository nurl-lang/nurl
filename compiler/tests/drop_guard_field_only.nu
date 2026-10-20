// drop_guard_field_only.nu — a `% Drop` struct whose field is a lock guard
// the program never holds anywhere else.
//
// The struct's drop glue drops its fields after its destructor, the guard
// through its library handle's drop hook (`WGuard_drop` for Fr). That hook
// is generic, and nothing asked for its instance for Fr: the program
// failed to link ("use of undefined value '@__nurl_fn.WGuard_drop__Fr'")
// unless a `( WGuard Fr )` binding somewhere happened to. The glue now
// asks for its fields' library handles when it is registered.

$ `stdlib/std/rwlock.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/core/string.nu`

: Fr { i v }

: Latch {
    ( WGuard Fr ) g
    Atomic pins
}

% Drop Latch { @ drop Latch x → v { : i _p ( atomic_sub . x pins 1 ) } }

@ take ( RwLocked Fr ) l Atomic pins → Latch {
    : i _p ( atomic_add pins 1 )
    ^ @ Latch { ( rw_write [Fr] l ) ( mem_dup pins ) }
}

@ main → i {
    : ( RwLocked Fr ) l ( rw_new [Fr] @ Fr { 0 } )
    : Atomic pins ( atomic_new 0 )
    : ~ i k 0
    ~ < k 3 {
        : Latch t ( take l pins )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `pins after the loop: ` ( nurl_str_int ( atomic_load pins ) ) ) )
    ^ 0
}
