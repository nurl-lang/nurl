// closure_capturing_a_field_local_of_a_parameter_and_growing_it: `: String nm . a name` captured by a closure that grows it, the caller viewing `. app name`
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #797).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #797: a closure growing a captured field local of a parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec String ) xs i n }

@ ext App a → v {
    : String nm . a name
    : ( @ v ) c \ → v { ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` ) }
    ( c )
}

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element long enough to live on the heap` ) )
    : App app @ App { ( string_from `a name long enough to live on the heap` ) xs 1 }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
