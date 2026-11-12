// mem_dup_beside_a_fresh_value_in_a_returned_join_lends_nothing_runs_clean: `^ ? c ( mem_dup a ) ( mks … )` over a struct that holds no view — the caller then hands `a`'s owner to a sink and reads the result.
// Agora #767: an arm that is a `( mem_dup x )` copy of a type with no view reaches nothing of x (__arm_dup_owns_all), so the join lends nothing; refused before as a borrow of the caller's argument.
// map: §2.8 | A2 | runs-clean | - | agora #767: a returned join of a mem_dup copy and a fresh value lends nothing
$ `stdlib/core/string.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ eat sink S s → i { ^ . s n }

@ f S a b c → S { ^ ? c ( mem_dup a ) ( mks `a fresh string long enough for a heap buffer` ) }

@ main → i {
    : S x ( mks `an element string long enough for a heap buffer` )
    : S e ( f x T )
    : i k ( eat x )
    ( nurl_println ( string_data . e name ) )
    ^ - + k . e n 2
}
