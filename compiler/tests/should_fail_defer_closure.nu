// should_fail_defer_closure.nu — `;` defer inside a closure body is
// rejected: the closure is emitted as its own function, so the defer
// would chain into the ENCLOSING function's cleanup blocks.

$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i i ) f \ i x → i {
        ; { ( nurl_print `no\n` ) }
        ^ x
    }
    ^ ( f 1 )
}
