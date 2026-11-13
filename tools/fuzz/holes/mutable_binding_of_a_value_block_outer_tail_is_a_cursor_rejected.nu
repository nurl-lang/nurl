$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }
// map: §ownership.blocks | A2 | rejected | - | agora #823: `: ~ e { s }` over an outer owner is the cursor `: ~ e s`, and a sink may not take a cursor while its owner is still read
@ main → i {
    : String s ( string_from `an outer owner long enough for a heap buffer` )
    : ~ String e { s }
    ( nurl_println_int ( eat e ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
