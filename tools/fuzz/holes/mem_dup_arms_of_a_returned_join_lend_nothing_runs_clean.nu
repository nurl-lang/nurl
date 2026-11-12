// mem_dup_arms_of_a_returned_join_lend_nothing_runs_clean: `^ ? c ( mem_dup a ) ( mem_dup a )` over a struct that holds no view — the caller then hands `a`'s owner on and reads the result.
// Closed by agora #688's arm rule (__arm_is_mem_dup, github#1807): an arm that is the `mem_dup` call owns its copy, and the join is summarised as lending nothing of `a`; refused before as a borrow of the caller's argument (agora #767).
// map: §2.8 | A2 | runs-clean | - | agora #767: a returned join of mem_dup copies lends nothing (closed by #688)
$ `stdlib/core/string.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ eat sink S s → i { ^ . s n }

@ f S a b c → S { ^ ? c ( mem_dup a ) ( mem_dup a ) }

@ main → i {
    : S x ( mks `an element string long enough for a heap buffer` )
    : S e ( f x T )
    : i k ( eat x )
    ^ - + k . e n 2
}
