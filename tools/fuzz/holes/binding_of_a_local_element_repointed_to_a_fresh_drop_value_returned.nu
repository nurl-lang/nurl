// binding_of_a_local_element_repointed_to_a_fresh_drop_value_returned: agora #335 — a binding of a local Vec's `vec_at` of a `% Drop` struct, given a fresh value by a straight-line `=`, then returned: it is owned at the `^`, and was refused as a lend of the local (formal's #1529 d1).
// Closed: a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag); a take through a `vec_get` slot is not made where the Vec is a capture of the closure being compiled (__vget_live, __pl_roots_capture); and an `=` at its binding's own depth replaces the value's lend pairs (mem_note_assign_lend; agora #335).
// main: refused ("this hands back what 'vec_at' may lend out of 'cs'…"); accepted with one drop each before #1465.
// map: §7.6 | A2 | runs-clean | - | agora #335: a binding re-pointed to a fresh Drop value, then returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { i fd String name }

% Drop Conn {
    @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop conn ` ( string_data . c name ) ) ) }
}

@ mk i fd → Conn {
    ^ @ Conn { fd ( string_from `a fresh connection name long enough for the heap` ) }
}

@ pick i k → Conn {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs ( mk 3 ) )
    : ~ Conn c ( vec_at [Conn] cs 0 )
    = c ( mk 4 )
    ^ c
}

@ main → i {
    : Conn a ( pick 1 )
    ( nurl_println_int . a fd )
    ^ 0
}
