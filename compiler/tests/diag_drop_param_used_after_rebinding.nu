// `: R q p` hands the % Drop parameter p over to q: a use of p after it
// is a use of a moved value (agora #768).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink R x → v { ( nurl_println_int . x n ) }

@ f ( Vec R ) log R p b keep → i { : R q p ? keep { ( eat q ) } {} ^ . p n }

@ main → i {
    : ( Vec R ) log ( vec_new [R] )
    ( nurl_println_int ( f log @ R { ( string_from `a heap string long enough` ) 1 } T ) )
    ( nurl_println_int ( f log @ R { ( string_from `b heap string long enough` ) 2 } F ) )
    ( nurl_println_int ( vec_len [R] log ) )
    ^ 0
}
