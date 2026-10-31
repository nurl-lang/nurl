// closure_hands_back_what_it_cannot_copy: a closure whose result cannot be copied — a `% Drop` value with no clone — handed back its parameter, its capture, a field of either, or what a lending call lent (`( vec_at rs 0 )`). Its caller takes a closure's result as its own, so the value was released by its owner and by the caller; nothing could make the caller a copy.
// Closed: such a result has to be the body's own — a parameter, a capture or a field of one is rejected where it is handed back, and a call whose callee may lend it is rejected at module end on the callee's final summary.
// main (before this PR): ASan heap-use-after-free.
// map: §7.5 | A2 | rejected | h219 | closure returns its %Drop capture by value: released by owner and caller
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Res r @ Res { v }
    : ( @ Res ) f \ → Res { r }
    : Res a ( f )
    : Res b ( f )
    ( nurl_println_int ( vec_len [i] . r buf ) )
    ^ 0
}
