// What a closure may do with a capture it cannot copy (h222, h224): move
// it out once — the env takes it over and the binding no longer drops it —
// or read it within the binding's frame, directly or through a struct
// that holds the closure. Each `Res` is dropped exactly once.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }
: Box2 { ( @ i ) get }

@ eat sink Res r → v {}

@ run_it ( @ v ) g → v { ( g ) }

@ moved_into_literal → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ Hold ) f \ → Hold { @ Hold { r 1 } }
    : Hold a ( f )
    ^ . a n
}

@ handed_to_sink → v {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ v ) f \ → v { ( eat r ) }
    ( f )
}

@ passed_on → v {
    : Res r @ Res { ( vec_new [i] ) }
    ( run_it \ → v { ( eat r ) } )
}

@ read_in_frame → i {
    : Res r @ Res { ( vec_new [i] ) }
    ( vec_push [i] . r buf 4 )
    : ( @ i ) f \ → i { ( vec_len [i] . r buf ) }
    : i n ( f )
    : Box2 b @ Box2 { \ → i { + 1 ( vec_len [i] . r buf ) } }
    : ( @ i ) g . b get
    ^ + n ( g )
}

@ returned_consuming → ( @ Hold ) {
    : Res r @ Res { ( vec_new [i] ) }
    ^ \ → Hold { @ Hold { r 2 } }
}

@ main → i {
    ( nurl_println_int ( moved_into_literal ) )
    ( handed_to_sink )
    ( passed_on )
    ( nurl_println_int ( read_in_frame ) )
    : ( @ Hold ) f ( returned_consuming )
    : Hold h ( f )
    ( nurl_println_int . h n )
    ^ 0
}
