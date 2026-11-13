// A % Drop parameter under another name (`: R q p`) is that parameter:
// handed to a sink on one path, read before, as p itself may be (agora
// #768). On the other path q drops it at its end, once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink R x → v { ( nurl_println_int . x n ) }

@ f ( Vec R ) log R p b keep → i { : R q p ( nurl_println_int . q n ) ? keep { ( eat q ) } {} ^ 1 }

@ main → i {
    : ( Vec R ) log ( vec_new [R] )
    ( nurl_println_int ( f log @ R { ( string_from `a heap string long enough` ) 1 } T ) )
    ( nurl_println_int ( f log @ R { ( string_from `b heap string long enough` ) 2 } F ) )
    ( nurl_println_int ( vec_len [R] log ) )
    ^ 0
}
