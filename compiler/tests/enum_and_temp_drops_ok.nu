// Enums and temporaries own what they hold exactly once (h231-h233): an
// enum's payload is lent to the arms — read, or handed to a `sink` as a
// copy — and the enum drops it; a temporary that cannot be copied is
// dropped where it is discarded or read for a field that owns nothing; a
// match on an enum a call handed over drops it. Each `Res` prints `drop`
// once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

: | Shape { Has Res Bare }

: | Msg { Text String Quiet }

@ consume sink String s → v {
    ( nurl_println ( string_data s ) )
}

@ mkr → Res {
    ^ @ Res { ( vec_new [i] ) }
}

@ mkh → Hold {
    ^ @ Hold { ( mkr ) 7 }
}

@ mks → Shape {
    ^ @ Shape { Has ( mkr ) }
}

@ mkm → Msg {
    ^ @ Msg { Text ( string_from `text` ) }
}

@ peek Shape s → i {
    ?? s { Has r → { ^ ( vec_len [i] . r buf ) } Bare → { ^ -1 } }
}

@ main → i {
    : Shape s ( mks )
    ?? s { Has r → { ( nurl_println_int ( vec_len [i] . r buf ) ) } Bare → {} }
    ( nurl_println_int ( peek s ) )
    : Msg m ( mkm )
    ?? m { Text t → { ( consume t ) } Quiet → {} }
    ?? m { Text t → { ( consume t ) } Quiet → {} }
    ( mkr )
    ( nurl_println_int . ( mkh ) n )
    ?? ( mks ) { Has r → { ( nurl_println_int ( vec_len [i] . r buf ) ) } Bare → {} }
    ?? ( mkm ) { Text t → { ( consume t ) } Quiet → {} }
    ^ 0
}
