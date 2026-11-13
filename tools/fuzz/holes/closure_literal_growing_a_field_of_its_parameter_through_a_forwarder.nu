// closure_literal_growing_a_field_of_its_parameter_through_a_forwarder: `( fwd app \ App x → v { : String nm . x name ( string_push_str nm … ) } )`
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #797).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #797: a closure literal growing a field local of its own parameter, through a forwarder
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec String ) xs i n }

@ fwd App a ( @ v App ) f → v { ( f a ) }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    : App app @ App { ( string_from `a name long enough to live on the heap` ) xs 1 }
    : s view ( string_data . app name )
    ( fwd app \ App x → v { : String nm . x name ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` ) } )
    ( nurl_eprintln view )
    ^ 0
}
