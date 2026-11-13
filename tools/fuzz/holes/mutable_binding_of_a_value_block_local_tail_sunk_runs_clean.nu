$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }
// map: §ownership.blocks | A2 | runs-clean | - | agora #823: a `: ~` binding of a value block whose tail is the block's own local owns it — the local dies with the block, so a sink may take it
@ main → i {
    : ~ String e { : ~ String u ( string_from `a block local long enough for a heap buffer` ) ( string_push_str u `!` ) u }
    : ~ ( Vec String ) w { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `an element long enough for a heap buffer` ) ) v }
    ( nurl_println_int ( eat e ) )
    ( nurl_println_int ( eatv w ) )
    ^ 0
}
