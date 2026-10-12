// A parameter read after the call that kept it (tools/fuzz/holes h207).
$ `stdlib/core/string.nu`

: H { String s }
: K { H h }

@ mk H h → K { ^ @ K { h } }

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
