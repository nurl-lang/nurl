// diag_removed_print_str.nu — the sibling migration hint.
//
// `nurl_print_str` printed the string plus a newline, which is exactly
// what `nurl_println` does; it was a duplicate under a second name and
// went with the print-family rename. Kept as a test because the
// diagnostic is the only thing that carries the mapping.
$ `stdlib/core/io.nu`

@ main → i {
    ( nurl_print_str `hello` )
    ^ 0
}
