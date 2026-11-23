// map: §7.6 | A2 | rejected | - | AGORA-959 guard: the join binding itself is not read after it was handed to an `inout` parameter, it moved where it owned
// AGORA-959: `y` may have moved (its `( mk )` arm), so a read of it is refused
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t → v {
    : P p @ P { ( mk ) 1 }
    : y ? > ( string_len t ) 0 . p s ( mk )
    = t y
    ( nurl_println_int ( string_len y ) )
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
