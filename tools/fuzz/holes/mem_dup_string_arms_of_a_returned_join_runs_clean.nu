// mem_dup_string_arms_of_a_returned_join_runs_clean: `^ ? c ( mem_dup ( vec_at [String] v 0 ) ) ( mem_dup ( vec_at [String] v 1 ) )` hands back a copy of one String element.
// Closed: a String join arm reads the copy's ownership off the value's own channel, before asking a callee (agora #688).
// main 3c4322c: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup copy of a String element as both arms of a returned ? join
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f ( Vec String ) v b c → String { ^ ? c ( mem_dup ( vec_at [String] v 0 ) ) ( mem_dup ( vec_at [String] v 1 ) ) }

@ main → i {
    : ~ ( Vec String ) va ( vec_new [String] )
    ( vec_push [String] va ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [String] va ( string_from `another element string long enough for the heap` ) )
    : String e ( f va T )
    : String e2 ( f va F )
    ^ - ( string_len e ) ( string_len e )
}
