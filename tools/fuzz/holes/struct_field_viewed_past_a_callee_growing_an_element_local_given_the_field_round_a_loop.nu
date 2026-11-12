// struct_field_viewed_past_a_callee_growing_an_element_local_given_the_field_round_a_loop: `: ~ String r ( vec_at . a xs 0 )`, then a loop growing `r` and giving it `. a name` — the grow reaches the field on the next round
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs) ends the caller's views of the argument's field paths' own buffers; a handle counts as an element's only where it is one for certain (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a struct field's view past a callee growing a local that holds an element, then the field, round a loop
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name ( Vec String ) xs }

@ ext App a → v {
    : ~ String r ( vec_at [String] . a xs 0 )
    : ~ i k 0
    ~ < k 2 {
        ( string_push_str r `, and a good deal more text so the buffer has to move somewhere else` )
        = r . a name
        = k + k 1
    }
}

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element long enough to live on the heap` ) )
    : App app @ App { ( string_from `a name long enough to live on the heap` ) xs }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
