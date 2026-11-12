// mem_dup_arm_beside_a_fresh_call_or_a_binding_runs_clean: one arm of a `?` join a `mem_dup` copy, the other a fresh call's result or the binding itself (`? c ( mem_dup x ) x`), on both paths.
// Closed: the copy's arm owns its value, the binding's arm lends it, and the join's flag says which per path (agora #688).
// main 3c4322c: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #688: a mem_dup arm beside a fresh call, and beside the binding it copies
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ f S a b c → S { ^ ? c ( mem_dup a ) ( mks `another fresh string long enough for the heap` ) }

@ main → i {
    : S x ( mks `an element string long enough for a heap buffer` )
    : S e ( f x T )
    : S e2 ( f x F )
    : S x2 ( mks `a second binding, copied or lent by the joins below` )
    : b c == . x2 n 1
    : S e3 ? c ( mem_dup x2 ) x2
    : S x3 ( mks `a third binding, lent or copied by the join below it` )
    : S e4 ? ! c ( mem_dup x3 ) x3
    ^ - + + + . e n . e2 n . e3 n . e4 n 4
}
