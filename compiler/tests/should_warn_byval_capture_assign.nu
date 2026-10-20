// should_warn_byval_capture_assign.nu — assigning to a closure-captured
// BY-VALUE binding is a silent dead store.
//
// A handle the closure assigns is captured by value (a snapshot), so the
// in-closure `= last …` writes a fresh per-invocation local: the closure
// returns the length of the string it just made, and the captured binding
// never changes. The program still compiles and runs, but the assignment
// emits a warning steering the user to the shapes that do share: a `: ~`
// number or flag the closure assigns, or a `: ~` multi-field struct — both
// captured by reference (and so unable to escape their frame).

$ `stdlib/core/string.nu`

@ make_greeter → ( @ i ) {
    : ~ String last ( string_from `none` )
    ^ \ → i { = last ( string_from `seen it` ) ^ ( string_len last ) }
}

@ main → i {
    : ( @ i ) c ( make_greeter )
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( c ) ) ) ( nurl_print `\n` )
    ^ 0
}
