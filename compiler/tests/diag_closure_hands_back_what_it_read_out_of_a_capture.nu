// diag_closure_hands_back_what_it_read_out_of_a_capture.nu — a closure
// hands back a binding of its captured Conn, a value that cannot be
// copied: the caller would own what the capture still owns, and each
// call would release it again. Refused, naming what it was read out of
// (agora #446).
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
