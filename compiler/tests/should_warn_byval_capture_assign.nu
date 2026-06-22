// should_warn_byval_capture_assign.nu — assigning to a closure-captured
// BY-VALUE binding is a silent dead store.
//
// The classic counter closure captures `n` by value (a snapshot), so the
// in-closure `= n + n 1` writes a fresh per-invocation local: it prints 1,1,1
// rather than 1,2,3 and never reaches the captured binding. The program still
// compiles and runs, but the assignment now emits a warning steering the user
// to the supported shared-mutation shape (a `: ~` multi-field struct captured
// by reference — which cannot escape its frame).
@ make_counter → ( @ i ) {
    : ~ i n 0
    ^ \ → i { = n + n 1 ^ n }
}

@ main → i {
    : ( @ i ) c ( make_counter )
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )
    ^ 0
}
