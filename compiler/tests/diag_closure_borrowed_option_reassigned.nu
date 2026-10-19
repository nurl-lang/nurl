// diag_closure_borrowed_option_reassigned.nu — a closure payload of an
// option binding borrows from it: giving the option a new value drops the
// env, and calling the payload after it is rejected.

$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    : ~ ? ( @ i i ) o @ ?( @ i i ) { T f }
    ?? o { T g → { = o @ ?( @ i i ) { F } ( nurl_println_int ( g 1 ) ) } F → {} }
    ^ 0
}
