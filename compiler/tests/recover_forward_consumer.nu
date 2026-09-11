// Forward consumers must release owned arguments on return and on panic.
$ `stdlib/std/panic.nu`

@ main → i {
    ( inspect_later ( nurl_str_cat `normal` ` argument` ) )
    ?? ( recover \ → v {
        ( crash_later ( nurl_str_cat `panic` ` argument` ) )
    } ) {
        T _ → { ^ 2 }
        F info → { ( panic_info_free info ) }
    }
    // An alias-returning callee must retain the argument for its caller.
    : s alias ( alias_later ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println alias )
    ( nurl_free alias )
    ^ 0
}

@ inspect_later s value → v {
    ( nurl_println value )
}

@ crash_later s value → v {
    ( panic value )
}

@ alias_later s value → s {
    ^ value
}
