// A parameter read after the call that kept it (tools/fuzz/holes h208).
$ `stdlib/core/string.nu`

: H { String s }
: K { H h }

@ mk H h → K { ^ @ K { h } }

@ kfree sink K k → v {}

@ outer H h → v {
    : K k ( mk h )
    ( kfree k )
    ( nurl_print ( string_data . h s ) )
}

@ main → i {
    : H x @ H { ( string_from `hello world, on the heap` ) }
    ( outer x )
    ( nurl_print `\n` )
    ^ 0
}
