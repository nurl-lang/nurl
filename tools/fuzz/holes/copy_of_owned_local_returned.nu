// copy_of_owned_local_returned: a copy of an owned local string handed back while the local itself was dropped on the way out — the caller read freed memory.
// map: FnOK | A1 | rejected | h116 | view (copy) of owned local string returned while local dropped
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
