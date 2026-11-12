// struct_field_viewed_past_a_callee_growing_a_handle_read_out_of_it: `@ ext App a → v { : String nm . a name ( string_push_str nm … ) }`, the caller keeping `( string_data . app name )` across `( ext app )`
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a struct field's view past a callee growing a handle read out of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ ext App a → v {
    : String nm . a name
    ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : App app @ App { ( string_from `a name long enough to live on the heap` ) 1 }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
