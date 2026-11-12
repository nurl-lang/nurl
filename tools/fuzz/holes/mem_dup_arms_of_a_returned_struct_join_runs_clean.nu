// mem_dup_arms_of_a_returned_struct_join_runs_clean: `^ ? c ( mem_dup a ) ( mem_dup b2 )` hands back the copy one arm made of a struct that owns a String.
// Closed: a `mem_dup` copy is an owner on the value's own channel (`__last_value_hown__`), which a `?` arm reads, so the join hands it over as it does a fresh call's result; a builtin has no callee answer for the join to ask (agora #688).
// main 3c4322c: accepted; LeakSanitizer: detected memory leaks (the chosen copy's String).
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup copy as both arms of a returned ? join over a struct owning a String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ f S a S b2 b c → S { ^ ? c ( mem_dup a ) ( mem_dup b2 ) }

@ main → i {
    : S x ( mks `an element string long enough for a heap buffer` )
    : S y ( mks `another element string long enough for the heap` )
    : S e ( f x y T )
    : S e2 ( f x y F )
    ^ - + . e n . e2 n 2
}
