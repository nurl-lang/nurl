// guard_reassign_owned.nu — reassigning a string binding whose first value
// came from a call that answers ownership per call (`pick` below lends its
// parameter on one path and hands back a fresh string on another). The
// binding is owned through its guard slot, not `__owned_strings__`; a
// reassignment used to store the new value into the binding alone, so
// nothing ever freed it (the compiler's own gen_ret leaked one register
// name per return this way). Each shape runs for several rounds: the live
// allocation count must not grow, and every value read back must be the
// one assigned last.

$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ pick s p i k → s {
    ? == k 0 { ^ p } {}
    ^ ( nurl_str_cat `fresh-` ( nurl_str_int k ) )
}

// A fresh owned call, a literal, and a tracked local, each assigned over a
// lent and an owned first value.
@ fresh_call i k → i {
    : ~ s acc ( pick `lent` k )
    = acc ( nurl_str_cat `%r` `12` )
    ^ ( nurl_str_len acc )
}

@ literal i k → i {
    : ~ s acc ( pick `lent` k )
    = acc `abc`
    ^ ( nurl_str_len acc )
}

@ tracked_local i k → i {
    : ~ s acc ( pick `lent` k )
    : s o ( nurl_str_cat `%r` `99` )
    = acc o
    ^ + ( nurl_str_len acc ) ( nurl_str_len o )
}

// Reassigned inside an arm only: the other path keeps the first value.
@ in_arm i k b c → i {
    : ~ s acc ( pick `lent` k )
    ? c { : s o ( nurl_str_cat `x` `yz` ) = acc o } {}
    ^ ( nurl_str_len acc )
}

// Reassigned once per iteration: every overwritten value is freed.
@ in_loop i k → i {
    : ~ s acc ( pick `lent` k )
    : ~ i i 0
    ~ < i 4 {
        : s o ( nurl_str_cat `n` ( nurl_str_int i ) )
        = acc o
        = i + i 1
    }
    ^ ( nurl_str_len acc )
}

// Handed back after the reassignment: the caller owns the NEW value.
@ reassign_ret i k → s {
    : ~ s acc ( pick `lent` k )
    ? > k 1 { = acc ( nurl_str_cat `new-` `value` ) } {}
    ^ acc
}

@ round → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 3 {
        = acc + acc ( fresh_call k )
        = acc + acc ( literal k )
        = acc + acc ( tracked_local k )
        = acc + acc ( in_arm k T )
        = acc + acc ( in_arm k F )
        = acc + acc ( in_loop k )
        : s r ( reassign_ret k )
        = acc + acc ( nurl_str_len r )
        = k + k 1
    }
    ^ acc
}

@ main → i {
    : i r1 ( round )
    : i l1 ( live )
    : i r2 ( round )
    : i r3 ( round )
    : i l3 ( live )
    ( puts ( nurl_str_int r1 ) )
    ( puts ( nurl_str_int + r2 r3 ) )
    ( puts ( reassign_ret 0 ) )
    ( puts ( reassign_ret 1 ) )
    ( puts ( reassign_ret 2 ) )
    ? == l1 l3 { ( puts `live allocations: steady` ) } { ( puts ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l3 l1 ) ) ) }
    ^ 0
}
