// A field written through a pointer is replaced: the value it held is
// dropped (docs/MEMORY.md §7.6), with no `mem_take` first. Fresh memory is
// filled, memory cast to a struct that owns something is zeroed, a value
// claimed with `mem_take` leaves a zero behind, a binding read out of the
// field keeps the value the store replaces, and a C out-parameter is a
// local passed `inout`. Run under LeakSanitizer by run_san_tests.sh: every
// replaced value must be released exactly once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Inner { String tag ( Vec i ) xs }

: State {
    String name
    ( Vec String ) items
    ? String note
    Inner inner
    i n
}

: H { ( Arc State ) a }

@ H_share H h → H { ^ @ H { ( arc_clone [State] . h a ) } }

@ H_drop sink H h → v {}

unsafe @ h_ptr H h → *State { ^ ( arc_ptr [State] . h a ) }

unsafe @ set_name H h s nm → v {
    : *State p ( h_ptr h )
    = . p name ( string_from nm )
}

unsafe @ add_items H h i k → v {
    : *State p ( h_ptr h )
    : ( Vec String ) v ( vec_new [String] )
    : ~ i left k
    ~ > left 0 { ( vec_push [String] v ( string_from `an item long enough for the heap` ) ) = left - left 1 }
    = . p items v
}

unsafe @ set_note H h s nm → v {
    : *State p ( h_ptr h )
    = . p note @ ?String { T ( string_from nm ) }
}

unsafe @ set_inner H h i x → v {
    : *State p ( h_ptr h )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs x )
    = . p inner @ Inner { ( string_from `an inner tag long enough for the heap` ) xs }
}

// The field's value leaves with `old`: the store hands it over.
unsafe @ swap_name H h s nm → String {
    : *State p ( h_ptr h )
    : String old . p name
    = . p name ( string_from nm )
    ^ old
}

: Node { String label ( @ i i ) f }

// Fresh memory: these stores fill it.
unsafe @ node_new s label → *Node {
    : *Node n # *Node ( nurl_alloc Z Node )
    = . n label ( string_from label )
    = . n f \ i x → i { ^ x }
    ^ n
}

// Memory a helper fills: zeroed when it was cast to *Node.
unsafe @ node_fill * Node n → v {
    = . n label ( string_from `filled by a helper, long enough for the heap` )
    = . n f \ i x → i { ^ * x 2 }
}

unsafe @ node_set_f * Node n i k → v {
    : String cap ( string_from `a captured string, long enough for the heap` )
    = . n f \ i x → i { ^ + + x k ( string_len cap ) }
}

unsafe @ node_free * Node n → v {
    : String l . n label
    ( mem_take l )
    : ( @ i i ) f . n f
    ( mem_take f )
    ( nurl_free # s n )
}

& `c` @ time inout i t → i

unsafe @ main → i {
    : H h @ H { ( arc_zero [State] ) }
    ( set_name h `the first name, long enough for the heap` )
    ( set_name h `the second name, long enough for the heap` )
    ( add_items h 3 )
    ( add_items h 2 )
    ( set_note h `a note long enough for the heap` )
    ( set_note h `another note long enough for the heap` )
    ( set_inner h 4 )
    ( set_inner h 5 )
    : String was ( swap_name h `the third name, long enough for the heap` )
    : *State p ( h_ptr h )
    ( nurl_println ( string_data was ) )
    ( nurl_println ( string_data . p name ) )
    ( nurl_println_int ( vec_len [String] . p items ) )
    ( nurl_println_int ?? ( vec_get [i] . . p inner xs 0 ) { T x → x F → -1 } )
    : *Node a ( node_new `a node label, long enough for the heap` )
    ( node_set_f a 1 )
    ( node_set_f a 2 )
    : ( @ i i ) fa . a f
    ( nurl_println_int ( fa 0 ) )
    ( node_free a )
    : *Node b # *Node ( nurl_malloc Z Node )
    ( node_fill b )
    : ( @ i i ) fb . b f
    ( nurl_println_int ( fb 21 ) )
    ( nurl_println ( string_data . b label ) )
    ( node_free b )
    : ~ i t 0
    : i r ( time t )
    ( nurl_println_int ? == t r 1 0 )
    ^ 0
}
