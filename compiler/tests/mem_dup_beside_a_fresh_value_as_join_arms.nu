// mem_dup_beside_a_fresh_value_as_join_arms.nu — a returned join of a
// `( mem_dup a )` copy and a fresh value (Agora #767): `?` arms in either
// order, a block arm ending in the copy, a nested join, `??` arms. The
// copied type holds no view, so the copy owns all it holds and the join
// lends nothing of `a`: the caller hands its argument to a `sink` and
// still reads the result. Each String is released once.

$ `stdlib/core/string.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ eat sink S s → i { ^ . s n }

@ copy_first S a b c → S { ^ ? c ( mem_dup a ) ( mks `a fresh name, long enough for the heap` ) }

@ copy_second S a b c → S { ^ ? c ( mks `a fresh name, long enough for the heap` ) ( mem_dup a ) }

@ copy_in_block S a b c → S { ^ ? c { ( mem_dup a ) } ( mks `a fresh name, long enough for the heap` ) }

@ nested S a i k → S { ^ ? == k 0 ( mem_dup a ) ? == k 1 ( mem_dup a ) ( mks `a fresh name, long enough for the heap` ) }

@ matched S a ? i o → S { ^ ?? o { T _ → ( mem_dup a ) F _ → ( mks `a fresh name, long enough for the heap` ) } }

@ show S e → i { ( nurl_println ( string_data . e name ) ) ^ . e n }

@ main → i {
    : S x ( mks `the caller's own name, long enough for the heap` )
    : S r1 ( copy_first x T )
    : S r2 ( copy_first x F )
    : S r3 ( copy_second x T )
    : S r4 ( copy_second x F )
    : S r5 ( copy_in_block x T )
    : S r6 ( nested x 1 )
    : S r7 ( nested x 2 )
    : S r8 ( matched x @ ?i { T 3 } )
    : S r9 ( matched x @ ?i { F 0 } )
    // The argument goes; the copies and the fresh values stay.
    : i k ( eat x )
    : i t + + + + + + + + ( show r1 ) ( show r2 ) ( show r3 ) ( show r4 ) ( show r5 ) ( show r6 ) ( show r7 ) ( show r8 ) ( show r9 )
    ^ - + k t 10
}
