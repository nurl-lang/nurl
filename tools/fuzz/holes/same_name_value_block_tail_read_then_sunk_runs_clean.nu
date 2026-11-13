// same_name_value_block_tail_read_then_sunk_runs_clean: `: String s { : String s … s }  ( println s )  ( eat s )`, and the `: ~` spelling grown first: the new binding owns the tail, read and then sunk
// main 191e572: heap-use-after-free (the block-local kept its drop). Read as `: s s`, the read after it would be refused as a use of a moved value.
// map: §7.6 | A2 | runs-clean | - | agora #823: a value block whose tail is its own local spelled like the binding (`: s { : s … s }`) gives the new binding its value, which is read and then sunk
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ eatv sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : String s { : String s ( string_from `a same-name block local long enough for a heap buffer` ) s }
    ( nurl_println ( string_data s ) )
    ( nurl_println_int ( eat s ) )
    : ~ String m { : String m ( string_from `a mutable same-name tail long enough for the heap` ) m }
    ( string_push_str m `!` )
    ( nurl_println_int ( eat m ) )
    ^ 0
}
