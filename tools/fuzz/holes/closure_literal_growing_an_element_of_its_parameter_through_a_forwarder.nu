// closure_literal_growing_an_element_of_its_parameter_through_a_forwarder: a closure literal growing `( vec_at . x xs 0 )` bound in its body, through a forwarder
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #797).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #797: a closure literal growing an element of its own parameter's field
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec String ) xs i n }

@ fwd App a ( @ v App ) f → v { ( f a ) }

@ main → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element long enough to live on the heap` ) )
    : App app @ App { ( string_from `a name long enough to live on the heap` ) vs 1 }
    : s view ( string_data ( vec_at [String] . app xs 0 ) )
    ( fwd app \ App x → v { : String e ( vec_at [String] . x xs 0 ) ( string_push_str e `, and a good deal more text so the buffer has to move somewhere else` ) } )
    ( nurl_eprintln view )
    ^ 0
}
