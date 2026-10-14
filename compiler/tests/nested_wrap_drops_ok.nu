// An option of an option, and a result whose error cannot be copied, own
// what they hold (h237, h238): bound, returned, discarded, matched (read,
// consumed, the inner option moved out) and lent to a function. Each `Res`
// prints `drop` once.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

@ eat sink Res r → v {
}

@ mkr → Res {
    ^ @ Res { ( vec_new [i] ) }
}

@ mkn → ?? Res {
    ^ @ ?? Res { T @ ?Res { T ( mkr ) } }
}

@ fails → !i Res {
    ^ @ !i Res { F ( mkr ) }
}

@ peek ?? Res p → i {
    ?? p { T q → { ^ 1 } F _ → { ^ 0 } }
}

@ main → i {
    : ?? Res a ( mkn )
    ( mkn )
    : ?? Res b ( mkn )
    ?? b { T q → { ?? q { T r → { ( nurl_println_int ( vec_len [i] . r buf ) ) } F _ → {} } } F _ → {} }
    : ?? Res c ( mkn )
    ?? c { T q → { ?? q { T r → { ( eat r ) } F _ → {} } } F _ → {} }
    : ?? Res d ( mkn )
    : ?Res inner ?? d { T x → { x } F _ → { @ ?Res { F } } }
    ( nurl_println_int ( peek a ) )
    : !i Res e ( fails )
    ( fails )
    ^ 0
}
