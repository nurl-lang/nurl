// An option or result of a value that cannot be copied (a `% Drop` value
// with no clone) drops its payload exactly once (h223, h226): bound, handed
// back, replaced, discarded, handed to a `sink`, matched — reading the
// payload, consuming it, moving it out — and lent to a function that
// matches it. Each `Res` prints `drop` once.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Holder { ? Res o i n }

@ eat sink Res r → v {}

@ eato sink ? Res o → v {}

@ fresh → ?Res {
    ^ @ ?Res { T @ Res { ( vec_new [i] ) } }
}

@ fresh_ok → !Res i {
    ^ @ !Res i { T @ Res { ( vec_new [i] ) } }
}

@ peek ? Res o → i {
    ?? o { T r → { ^ ( vec_len [i] . r buf ) } F _ → { ^ 0 } }
}

@ bound → v {
    : ?Res p ( fresh )
    : !Res i q ( fresh_ok )
}

@ replaced → v {
    : ~ ? Res p ( fresh )
    = p @ ?Res { F }
    ( nurl_println `replaced` )
}

@ discarded → v {
    ( fresh )
    ( fresh_ok )
}

@ sunk → v {
    : ?Res p ( fresh )
    ( eato p )
}

@ matched → v {
    : ?Res p ( fresh )
    ?? p { T r → { ( nurl_println_int ( vec_len [i] . r buf ) ) } F _ → {} }
    : ?Res q ( fresh )
    ?? q { T r → { ( eat r ) } F _ → {} }
    : ?Res w ( fresh )
    : Res m ?? w { T r → { r } F _ → { @ Res { ( vec_new [i] ) } } }
}

@ lent → v {
    : ?Res p ( fresh )
    ( nurl_println_int ( peek p ) )
    ( nurl_println_int ( peek p ) )
}

@ in_field → v {
    : Holder h @ Holder { ( fresh ) 1 }
    ?? . h o { T r → { ( nurl_println_int ( vec_len [i] . r buf ) ) } F _ → {} }
}

@ main → i {
    ( bound )
    ( replaced )
    ( discarded )
    ( sunk )
    ( matched )
    ( lent )
    ( in_field )
    ^ 0
}
