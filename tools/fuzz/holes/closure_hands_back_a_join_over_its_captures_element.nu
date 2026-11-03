// closure_hands_back_a_join_over_its_captures_element: a closure hands back a binding of a join one arm of which is an element of its captured Vec of a Drop type.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back a binding of a join one arm of which is an element of its captured Vec of a Drop type
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }
: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
    : ( @ Conn b ) f \ b k → Conn { : Conn c ? k ( vec_at [Conn] cs 0 ) @ Conn { ( string_from `fresh` ) } ^ c }
    : Conn a ( f T )
    ^ 0
}
