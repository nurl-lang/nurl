// closure_hands_back_a_payload_of_its_captures_element: a closure hands back the ?? payload of vec_get on its captured Vec of a Drop type.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back the ?? payload of vec_get on its captured Vec of a Drop type
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
    : ( @ Conn ) f \ → Conn {
        ?? ( vec_get [Conn] cs 0 ) { T e → { ^ e } F → {} }
        ^ @ Conn { ( string_from `fresh` ) }
    }
    : Conn a ( f )
    ^ 0
}
