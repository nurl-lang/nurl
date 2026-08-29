// eprint_int_family.nu — the print family is one rule on BOTH streams.
//
// `print` = no newline, `println` = newline, `_int` = the integer
// overload, `eprint`/`eprintln` = the same pair on stderr. The `_int`
// half was missing on stderr, so a diagnostic that printed a number had
// to build a string first — `( nurl_eprint ( nurl_str_int n ) )` — which
// allocates, and leaks unless the caller binds and frees it.
//
// The runner folds stdout and stderr into one OUTPUT block, so the
// golden also pins the INTERLEAVING: nurl_eprint drains stdout before
// writing, which is what keeps a redirected stream in program order.
$ `stdlib/core/io.nu`

@ main → i {
    ( nurl_print `out:` )
    ( nurl_print_int 41 )
    ( nurl_println `` )
    ( nurl_eprint `err:` )
    ( nurl_eprint_int -7 )
    ( nurl_eprintln `` )
    ( nurl_eprintln_int 0 )
    ( nurl_eprintln_int -9223372036854775807 )
    ( nurl_println_int 1234567890 )
    ^ 0
}
