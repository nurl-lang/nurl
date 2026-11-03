// diag_returned_closure_option_capture_no_copy.nu — a closure returned
// right here captures an option of a `% Drop` struct with no Clone, which
// the function releases when it returns. The environment cannot be given
// a copy of its own, so running the closure would read freed memory
// (agora #463): refused at the literal.
$ `stdlib/core/string.nu`

: Res { String name }

% Drop Res {
    @ drop Res r → v { ( nurl_println `dropped` ) }
}

@ cap → ( @ i ) {
    : ?Res x @ ?Res { T @ Res { ( string_from `a resource name long enough for the heap` ) } }
    ^ \ → i { ?? x { T r → { ^ ( string_len . r name ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
