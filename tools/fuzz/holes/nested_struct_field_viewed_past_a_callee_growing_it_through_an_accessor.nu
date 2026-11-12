// nested_struct_field_viewed_past_a_callee_growing_it_through_an_accessor: `: String nm . ( innerof o ) name` grown in the callee, the caller keeping `( string_data . . out inner name )`
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a nested struct field's view past a callee growing it through an accessor
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: In { String name i n }
: Out { In inner i m }

@ innerof Out o → In { ^ . o inner }

@ ext Out o → v {
    : String nm . ( innerof o ) name
    ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : Out out @ Out { @ In { ( string_from `a name long enough to live on the heap` ) 1 } 2 }
    : s view ( string_data . . out inner name )
    ( ext out )
    ( nurl_eprintln view )
    ^ 0
}
