// map: §7.6 | A2 | rejected | - | AGORA-959 guard: two field joins handed to one `inout` parameter on one line stay refused
// AGORA-959: only a row codegen marks `ak` loses the field borrow; this one keeps the rule as before
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t b c → v {
    : P p @ P { ( mk ) 1 }
    : y ? c . p s ( mk )
    : P q @ P { ( mk ) 2 }
    : z ? c . q s ( mk )
    ? c { = t y } { = t z }
}

@ main → i {
    : ~ String t ( mk )
    ( f t T )
    ( nurl_println_int ( string_len t ) )
    ( f t F )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
