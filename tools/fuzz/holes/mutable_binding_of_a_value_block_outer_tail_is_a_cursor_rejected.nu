// mutable_binding_of_a_value_block_outer_tail_is_a_cursor_rejected: `: String s …  : ~ String e { s }  ( eat e )  ( println s )`: `: ~ e { s }` is the cursor `: ~ e s`, and a sink may not take a cursor
// main 191e572: refused, as `: ~ e s` is; pinned (a `: ~` of an outer tail keeps the walk's cursor reading).
// map: §7.6 | A2 | rejected | - | agora #823: `: ~ e { s }` over an outer owner is the cursor `: ~ e s`, and a sink may not take a cursor while its owner is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : String s ( string_from `an outer owner long enough for a heap buffer` )
    : ~ String e { s }
    ( nurl_println_int ( eat e ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
