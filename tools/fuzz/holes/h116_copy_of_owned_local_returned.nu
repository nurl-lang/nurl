// H116: a copy of an owned local string handed back while the local itself was dropped on the way out — the caller read freed memory.
$ `stdlib/core/string.nu`

@ f s a → s {
    : s x ( nurl_str_cat a `-tail` )
    : s y x
    ^ y
}

@ main → i {
    : s r ( f `head` )
    ( nurl_print r ) ( nurl_print `\n` )
    ^ 0
}
