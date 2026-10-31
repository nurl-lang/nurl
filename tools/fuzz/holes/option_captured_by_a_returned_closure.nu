// option_captured_by_a_returned_closure: a returned closure over an option-of-String parameter was not recorded as lending it (only a handle or a closure capture was), so the caller gave the option a new value — releasing the String — and then called the closure.
// Closed: a captured parameter of any type that owns memory or holds a view is lent by the returned closure (`retclo`), so h299's rule reaches it.
// main (before this PR): AddressSanitizer reported heap-use-after-free in the closure's string_len.
// map: §2.11 | A2 | rejected | h302 | a returned closure over an option-of-String parameter was not recorded as lending it; the caller gave the option a new value, then called the closure
$ `stdlib/core/string.nu`

@ mk ? String o → ( @ i ) { ^ \ → i { ?? o { T x → { ^ ( string_len x ) } F → { ^ 0 } } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `abcd` ) }
    : ( @ i ) f ( mk o )
    = o @ ?String { F # String 0 }
    ( nurl_println_int ( f ) )
    ^ 0
}
