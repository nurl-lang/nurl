// closure_hands_back_a_bound_enum_payload_of_its_capture: a closure hands back a binding of the payload of an enum it captures.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back a binding of the payload of an enum it captures
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }
: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

: | E { Some ( Vec String ) None }

: | EC { Has Conn Nope }

@ main → i {
    : EC e @ EC { Has @ Conn { ( string_from `an enum payload name long enough to live on the heap` ) } }
    : ( @ Conn ) f \ → Conn { ?? e { Has c → { : Conn d c ^ d } Nope → {} } ^ @ Conn { ( string_from `fresh` ) } }
    : Conn a ( f )
    ^ 0
}
