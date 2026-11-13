// A `: ~` copy of the binding it shadows is a borrow of it — the cursor
// idiom — so handing it to a sink is refused, as for `: ~ String u s`
// (agora #792; a use-after-free on main).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String t i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ eatr sink R x → v { ( nurl_println_int . x n ) }

@ eatv sink ( Vec i ) x → v { ( nurl_println_int ( vec_len [i] x ) ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    { : ~ String s s ( eat s ) }
    ^ 0
}
