// closure_into_field_views_capture: a closure stored into a struct that outlives the frame it was made in kept only a view of the String it captured: the env was copied bitwise (nurl_closure_clone copies a closure's captured closures, not the values it views), the frame dropped the String at its end, and calling the struct's closure read freed memory. Three spellings: a literal assigned to a field (`= . r f \ …`), a closure binding put in a struct literal, and one assigned to a field.
// Closed: a closure stored into a struct field or a slice owns its captures — nurl_closure_adopt copies in what the env only viewed (a literal's env in place, a binding's in a copy) and switches it to the descriptor that releases them.
// main (before this PR): AddressSanitizer, heap-use-after-free in the closure.
// map: §7.5 | A2 | runs-clean | h195 | closure stored into returned struct only views captured String freed at frame end
$ `stdlib/core/string.nu`

: Box { String name ( @ i i ) f }

@ assigned → Box {
    : String cap ( string_from `captured string, long enough for the heap` )
    : ~ Box b @ Box { ( string_from `a` ) \ i x → i { ^ x } }
    = . b f \ i x → i { ^ + x ( string_len cap ) }
    ^ b
}

@ in_literal → Box {
    : String cap ( string_from `captured string, long enough for the heap` )
    : ( @ i i ) g \ i x → i { ^ + x ( string_len cap ) }
    ^ @ Box { ( string_from `b` ) g }
}

@ binding_assigned → Box {
    : String cap ( string_from `captured string, long enough for the heap` )
    : ~ Box b @ Box { ( string_from `c` ) \ i x → i { ^ x } }
    : ( @ i i ) g \ i x → i { ^ + x ( string_len cap ) }
    = . b f g
    ^ b
}

@ main → i {
    : Box a ( assigned )
    : Box b ( in_literal )
    : Box c ( binding_assigned )
    : ( @ i i ) fa . a f
    : ( @ i i ) fb . b f
    : ( @ i i ) fc . c f
    ( nurl_println_int + + ( fa 1 ) ( fb 2 ) ( fc 3 ) )
    ^ 0
}
