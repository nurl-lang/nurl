// binding_of_a_value_block_of_an_outer_binding_read_beside_it_runs_clean: agora #615 guard — `: String e { ( nurl_println_int 1 ) s }` with s bound before the block: e views s, and both are read after it.
// Guard: only a binding the block made itself is the block's value to the new binding's drop flag; a binding from outside it is lent as before and stays readable, where the bare `: String e s` would move it.
// main 0b31adec: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #615 guard: a binding of a value block whose tail is an outer binding, both read after it
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `outer string long enough for a heap buffer` )
    : String e { ( nurl_println_int 1 ) s }
    ( nurl_println_int + ( string_len e ) ( string_len s ) )
    ^ 0
}
