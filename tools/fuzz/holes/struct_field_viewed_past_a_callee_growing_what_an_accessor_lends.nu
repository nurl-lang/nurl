// struct_field_viewed_past_a_callee_growing_what_an_accessor_lends: `: String nm ( nameof a )` grown in the callee, `@ nameof App a → String { ^ . a name }`, the caller keeping `( string_data . app name )`
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a struct field's view past a callee growing what an accessor lends of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }

@ nameof App a → String { ^ . a name }

@ ext App a → v {
    : String nm ( nameof a )
    ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : App app @ App { ( string_from `a name long enough to live on the heap` ) 1 }
    : s view ( string_data . app name )
    ( ext app )
    ( nurl_eprintln view )
    ^ 0
}
