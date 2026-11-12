// mem_dup_arms_of_a_bound_join_over_vec_elements_runs_clean: `: S e ? c ( mem_dup ( vec_at [S] va 0 ) ) ( mem_dup ( vec_at [S] va 1 ) )` binds the copy one arm made of a Vec's element.
// Closed: the join's binding owns the copy, as it owns a fresh call's result (agora #688).
// main 3c4322c: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup copy of a Vec element as both arms of a bound ? join
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks `an element string long enough for a heap buffer` ) )
    ( vec_push [S] va ( mks `another element string long enough for the heap` ) )
    : b c == ( vec_len [S] va ) 2
    : S e ? c ( mem_dup ( vec_at [S] va 0 ) ) ( mem_dup ( vec_at [S] va 1 ) )
    ^ - . e n 1
}
