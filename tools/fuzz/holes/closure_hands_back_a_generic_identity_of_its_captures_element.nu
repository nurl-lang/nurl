// closure_hands_back_a_generic_identity_of_its_captures_element: a closure hands back a binding of a generic identity of an element of its captured Vec of a Drop type.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back a binding of a generic identity of an element of its captured Vec of a Drop type
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ id [T] T x → T { ^ x }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
    : ( @ Conn ) f \ → Conn { : Conn c ( id [Conn] ( vec_at [Conn] cs 0 ) ) ^ c }
    : Conn a ( f )
    ^ 0
}
