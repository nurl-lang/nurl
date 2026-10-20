// block_after_cond.nu — a block statement right after a two-armed `?`.
//
// A bare `{ … }` is a statement: it runs, and what it declares is dropped
// at its `}` — the way to let a lock guard go before the function ends.
// After `? c { … } { … }` the arity check read a following `{` as the
// tail of an under-operated condition (`? & a b c d { … }`), and refused
// the program. Both arms braced, nothing was taken bare: the `{` is the
// block statement it looks like. An arm taken bare still makes the check
// fire (arity_strict_nary.nu).

$ `stdlib/core/string.nu`
$ `stdlib/std/rwlock.nu`

@ step ( RwLocked i ) l i x → i {
    ? == x 0 { ^ -1 } {}
    {
        : ( WGuard i ) g ( rw_write [i] l )
        ( wguard_update [i] g \ inout i v → v { = v + v x } )
    }
    // The guard went at the `}` above: reading the value does not wait.
    ^ ( rw_get [i] l )
}

@ main → i {
    : ( RwLocked i ) l ( rw_new [i] 10 )
    ( nurl_println ( nurl_str_cat `step: ` ( nurl_str_int ( step l 5 ) ) ) )
    ( nurl_println ( nurl_str_cat `zero: ` ( nurl_str_int ( step l 0 ) ) ) )
    ^ 0
}
