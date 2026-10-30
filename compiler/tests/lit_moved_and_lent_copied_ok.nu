// lit_moved_and_lent_copied_ok.nu — a returned literal moves a local into
// one field and keeps another field from a call that lends that same local:
// the lent field is copied (agora #189), so the result owns two Strings,
// not one twice. (It was refused before as "kept as is";
// diag_lit_lent_kept keeps the refusal for a closure's literal.)
$ `stdlib/core/string.nu`

: Two { String a String b }

@ same String x → String { ^ x }

@ mk → Two {
    : String t ( string_from `a string moved in and lent beside it` )
    ^ @ Two { t ( same t ) }
}

@ main → i {
    : Two w ( mk )
    ( nurl_println ( string_data . w a ) )
    ( nurl_println ( string_data . w b ) )
    ^ 0
}
