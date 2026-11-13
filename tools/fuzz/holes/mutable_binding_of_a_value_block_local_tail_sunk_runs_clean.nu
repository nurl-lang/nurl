// mutable_binding_of_a_value_block_local_tail_sunk_runs_clean: `: ~ String e { : ~ String u … u }  ( eat e )` (and the Vec form): the block-local dies with the block, so e owns its value and a sink may take it
// main 191e572: runs clean. Pinned: read as the cursor `: ~ e u`, it would be refused.
// map: §7.6 | A2 | runs-clean | - | agora #823: a `: ~` binding of a value block whose tail is the block's own local owns it — the local dies with the block, so a sink may take it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : ~ String e { : ~ String u ( string_from `a block local long enough for a heap buffer` ) ( string_push_str u `!` ) u }
    : ~ ( Vec String ) w { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `an element long enough for a heap buffer` ) ) v }
    ( nurl_println_int ( eat e ) )
    ( nurl_println_int ( eatv w ) )
    ^ 0
}
