// struct_field_viewed_past_a_callee_growing_what_a_function_named_like_an_accessor_lends: `@ vec_at__pick App a → String { ^ . a name }` — a function of the program, not the library accessor — its result grown in the callee
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs) ends the caller's views of the argument's field paths' own buffers; a handle counts as an element's only where it is one for certain (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a struct field's view past a callee growing what a program function named like vec_at lends
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ vec_at__pick App a → String { ^ . a name }

@ ext App a → v {
    : String r ( vec_at__pick a )
    ( string_push_str r `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : App app @ App { ( string_from `a name long enough to live on the heap` ) 1 }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
