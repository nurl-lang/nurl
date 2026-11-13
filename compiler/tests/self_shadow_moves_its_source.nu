// `: T s s` hands the value of the s it shadows over to the new s, as
// `: T u s` does (agora #792): in the same scope, in a block, of a % Drop
// struct and of a Vec, read and handed to a sink. Each value is
// released once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String t i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ eatr sink R x → v { ( nurl_println_int . x n ) }

@ eatv sink ( Vec i ) x → v { ( nurl_println_int ( vec_len [i] x ) ) }

@ same_scope → v {
    : ~ String s ( string_from `same scope, long enough for a heap buffer` )
    : String s s
    ( eat s )
}

@ nested_read → v {
    : ~ String s ( string_from `nested read, long enough for a heap buffer` )
    { : String s s ( nurl_println ( string_data s ) ) }
}

@ drop_struct → v {
    : R s @ R { ( string_from `a struct field, long enough for a heap buffer` ) 7 }
    ? T { : R s s ( eatr s ) } {}
}

@ drop_struct_keep → v {
    : R s @ R { ( string_from `a struct field, long enough for a heap buffer` ) 8 }
    { : R s s ( nurl_println_int . s n ) }
}

@ vec_shadow → v {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s 3 )
    { : ( Vec i ) s s ( eatv s ) }
}

@ main → i {
    ( same_scope )
    ( nested_read )
    ( drop_struct )
    ( drop_struct_keep )
    ( vec_shadow )
    ^ 0
}
