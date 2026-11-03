// closure_hands_back_its_capture_bound: a closure hands back a binding of its Drop-type capture, so a second call releases it again.
// Closed: a closure's ^ of a value that cannot be copied is refused when the value was read out of a capture or a parameter of the closure, by any route its source expression or a ?? payload names — the body's own owned value is all it can hand over (agora #446).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.3 | A2 | rejected | - | agora #446: a closure hands back a binding of its Drop-type capture, so a second call releases it again
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

: | E { Some ( Vec String ) None }

@ main → i {
    : Conn p @ Conn { ( string_from `a capture name long enough to live on the heap for sure` ) }
    : ( @ Conn ) f \ → Conn { : Conn c p ^ c }
    : Conn x ( f )
    : Conn y ( f )
    ^ 0
}
