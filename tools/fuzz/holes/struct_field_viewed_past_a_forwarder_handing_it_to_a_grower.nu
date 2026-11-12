// struct_field_viewed_past_a_forwarder_handing_it_to_a_grower: `@ ext2 Out o → v { ( ext . o app ) }` with ext growing `. a name` through a local, the caller keeping `( string_data . . out app name )` across `( ext2 out )`
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a struct field's view past a forwarder handing the field to a grower
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }
: Out { App app i m }

@ ext App a → v {
    : String nm . a name
    ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` )
}

@ ext2 Out o → v { ( ext . o app ) }

@ main → i {
    : Out out @ Out { @ App { ( string_from `a name long enough to live on the heap` ) 1 } 2 }
    : s view ( string_data . . out app name )
    ( ext2 out )
    ( nurl_eprintln view )
    ^ 0
}
