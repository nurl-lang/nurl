// eprint_int_family.nu — the print family is one rule on BOTH streams.
//
// `print` = no newline, `println` = newline, `_int` = the integer
// overload, `eprint`/`eprintln` = the same pair on stderr. The `_int`
// half was missing on stderr, so a diagnostic that printed a number had
// to build a string first — `( nurl_eprint ( nurl_str_int n ) )` — which
// allocates, and leaks unless the caller binds and frees it.
//
// Every stdout write comes first and every stderr write after, and that
// is deliberate: the posix runner captures the two streams through one
// pipe (`> out 2>&1`, real interleaving) while run_tests.ps1 redirects
// them into two buffers and concatenates. A test that alternated between
// them would assert the HARNESS's merge order, not the program's — which
// is how the first draft of this file passed on Linux and failed on
// Windows with "same lines, different order". Splitting the streams
// makes the record identical under both.
$ `stdlib/core/io.nu`

@ main → i {
    ( nurl_print `out:` )
    ( nurl_print_int 41 )
    ( nurl_println `` )
    ( nurl_println_int 1234567890 )
    ( nurl_eprint `err:` )
    ( nurl_eprint_int -7 )
    ( nurl_eprintln `` )
    ( nurl_eprintln_int 0 )
    ( nurl_eprintln_int -9223372036854775807 )
    ^ 0
}
