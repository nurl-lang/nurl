// closure_moving_loop_hands_a_payload_of_its_captures_element_to_a_sink: AGORA-479 guard — a closure's `~ x t { ?? x { T s → ( eat s ) … } }` over its captured Vec of options, run twice: the payload is not moved out of the element, which the Vec still holds
// AGORA-479 guard: refused, as on main 029b01dd - the moving-loop exception (the element itself) does not reach a payload of it
// map: §2.10 | A2 | rejected | - | AGORA-479 guard: a closure's `~` loop hands a payload of its captured Vec's element to a sink, run twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Vec ? String ) t ( vec_new [? String] )
    ( vec_push [? String] t @ ?String { T ( string_from `first string long enough for a heap buffer here` ) } )
    : ( @ v ) wipe \ → v { ~ x t { ?? x { T s → { ( eat s ) } F → {} } } }
    ( wipe )
    ( wipe )
    ^ 0
}
