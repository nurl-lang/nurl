// binding_of_a_value_block_of_its_own_local_only_read_runs_clean: agora #615 guard — `: String e { : String s … s }` and `: ~ ( Vec String ) w { : ~ ( Vec String ) u … u }`, read and grown but handed to nobody: the value is released once, at the scope's end.
// Guard: e is a cursor over s to its drop flag, as `: e s` is, and the `: ~` binding is read as before; the block's locals release the values once, at the scope's end (ASan + strict LSan).
// main 0b31adec: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #615 guard: a binding of a value block of the block's own local, only read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String e { : String s ( string_from `inner string long enough for a heap buffer` ) s }
    ( nurl_println_int ( string_len e ) )
    : ~ ( Vec String ) w { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) ) u }
    ( vec_push [String] w ( string_from `a second element string long enough for the heap` ) )
    ( nurl_println_int # i ( vec_len [String] w ) )
    ^ 0
}
