// reassigned_struct_cursor_handed_to_a_sink_runs_clean: as reassigned_vec_cursor_handed_to_a_sink_runs_clean, a struct owning a String
// Closed: a sink takes a cursor's value from its source only where the cursor still holds that very value, by the value's identity (mem_alias_src_leaves), as a store or a return moving the cursor on already asked (agora #668).
// main 9052104: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #668: as that probe, a struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { String s i n }

@ eat sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ eats sink String x → i { ^ ( string_len x ) }

@ eatw sink W x → i { ^ . x n }

@ mkv s t → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from t ) ) ^ v }

@ main → i {
    : ~ W u @ W { ( string_from `a struct string long enough for a heap buffer` ) 1 }
    : ~ W w u
    = w @ W { ( string_from `another struct string long enough for heap` ) 2 }
    ( nurl_println_int ( eatw w ) )
    ^ 0
}
