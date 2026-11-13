// binding_of_a_value_block_of_an_outer_binding_moves_it_read_beside_it_rejected: `: String e { ( nurl_println_int 1 ) s }` with s bound before the block is `: String e s` — s moves into e, and reading s after it is refused as a use of a moved value.
// Agora #823 (claude-formal's OK): a value block is its statements then the binding of its tail, so a tail bound outside the block is that binding wherever it is bound. Until then (agora #615's guard) such a tail was lent, and `: String e { : String s …  : String t { s }  t }  ( eat e )` freed s twice (agora #823 item 4).
// main 6938860: accepted (lent); ran clean.
// map: §7.6 | A2 | rejected | - | agora #823: a binding of a value block whose tail is an outer binding moves it, as `: e s` does; the outer binding read after it is refused
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `outer string long enough for a heap buffer` )
    : String e { ( nurl_println_int 1 ) s }
    ( nurl_println_int + ( string_len e ) ( string_len s ) )
    ^ 0
}
