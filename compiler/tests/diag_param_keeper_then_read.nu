// A parameter read after the call that kept it (tools/fuzz/holes h207). An
// `in` parameter handed back in a literal is lent (D4c, AGORA-995): `mk`
// takes its argument over, so it says `sink`.
$ `stdlib/core/string.nu`

: H { String s }
: K { H h }

@ mk sink H h → K { ^ @ K { h } }

@ mid H h → v {
    : K k ( mk h )
    ( nurl_print ( string_data . . k h s ) )
}

@ outer H h → v {
    ( mid h )
    ( nurl_print ( string_data . h s ) )
}

@ main → i {
    : H x @ H { ( string_from `hello world, on the heap` ) }
    ( outer x )
    ( nurl_print `\n` )
    ^ 0
}
