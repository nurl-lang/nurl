// closure_var_lent_reassigned_ok.nu — a `~` closure binding given a
// closure its owner lends, then one of its own again (agora #153): the
// borrow ends with the new value, and calling it while the owner lives is
// fine.

: Holder {
    ( @ i ) cb
    i pad
}

@ take_holder sink Holder h → v {}

@ main → i {
    : i x 42
    : ~ ( @ i ) f \ → i { ^ 0 }
    : Holder h @ Holder { \ → i { ^ x } 0 }
    = f . h cb
    ( nurl_println ( nurl_str_int ( f ) ) )
    = f \ → i { ^ 7 }
    ( take_holder h )
    ( nurl_println ( nurl_str_int ( f ) ) )
    ^ 0
}
