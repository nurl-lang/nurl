// A string global holds literals in safe code: handing it a fresh string to
// own would let the next assignment free that string under a reader in
// another thread (h273). Text that changes at run time lives in a
// `( Locked String )` set at start.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: ~ s g_label `none`

@ relabel s a → v { = g_label ( nurl_str_cat a `!` ) }

@ keep_literal → v { = g_label `fixed` }

unsafe @ main → i {
    ( keep_literal )
    ( relabel `x` )
    ^ 0
}
