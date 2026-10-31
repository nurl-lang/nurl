// drop_value_stored_into_two_literals: agora #157 — a move-only value (a user `% Drop` type, a trait object) stored into an owner (drop_value_stored_into_two_literals).
// Closed: the store row covers move-only values (agora #157).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h558 | agora #157: drop_value_stored_into_two_literals
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mkr → Res {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 7 )
    ^ @ Res { b }
}

: Box1 { Res r i pad }

@ main → i {
    : Res a ( mkr )
    : Box1 h @ Box1 { a 0 }
    : Box1 h2 @ Box1 { a 1 }
    ^ 0
}
