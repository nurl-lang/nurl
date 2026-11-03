// closure_hands_back_a_bound_field_of_its_capture: a closure hands back a binding of a Drop-type field of a struct it captures.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back a binding of a Drop-type field of a struct it captures
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }
: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

: | E { Some ( Vec String ) None }

: Pair { Conn a i k }

@ main → i {
    : Pair p @ Pair { @ Conn { ( string_from `a field name long enough to live on the heap for sure` ) } 1 }
    : ( @ Conn ) f \ → Conn { : Conn c . p a ^ c }
    : Conn x ( f )
    ^ 0
}
