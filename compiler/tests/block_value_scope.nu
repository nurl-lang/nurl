// block_value_scope.nu — a block that computes a number for a `:` binding
// drops what it binds at its `}`.
//
// `: i root { : PageWrite pw ( new_page ) ( page_id pw ) }` takes a lock
// guard to read one number off a page; the guard has to go where the block
// ends. A bare block statement already dropped its bindings there; a block
// whose value is bound did not — the guard lived to the end of the
// function, and the next request for the same lock, in that function,
// waited for itself. The value is a number, which cannot point into what
// the block bound, so the block is a scope of its own.

$ `stdlib/std/rwlock.nu`
$ `stdlib/core/string.nu`

@ bump ( RwLocked i ) l → i {
    : i before {
        : ( WGuard i ) g ( rw_write [i] l )
        ( wguard_apply [i i] g \ inout i v → i { = v + v 1 ^ v } )
    }
    // The guard went at the `}`: this does not wait.
    : i after ( rw_get [i] l )
    ^ + * before 100 after
}

@ main → i {
    : ( RwLocked i ) l ( rw_new [i] 4 )
    ( nurl_println ( nurl_str_cat `bump: ` ( nurl_str_int ( bump l ) ) ) )
    ( nurl_println ( nurl_str_cat `again: ` ( nurl_str_int ( bump l ) ) ) )
    ^ 0
}
