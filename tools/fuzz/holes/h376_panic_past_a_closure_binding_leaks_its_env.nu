// H376: a closure bound to a local, handed to a call that panics: the binding's env is dropped at its scope's exit, which the panic skipped — nothing in the journal named it.
// Closed: every closure binding's value and owner slot are in the function's closure frame table, registered once (nurl_jframe_clo_drop, agora #131).
// v0.79.0: accepted; LSan reported a direct leak (the env).
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ run ( @ v ) f → v { ( nurl_panic `boom` ) }

@ case → v {
    : String a ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) f \ → v { ( nurl_println ( string_data a ) ) }
    ( run f )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( case ) } )
    ( nurl_println `recovered` )
    ^ 0
}
