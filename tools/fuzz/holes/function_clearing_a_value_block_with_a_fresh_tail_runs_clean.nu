// function_clearing_a_value_block_with_a_fresh_tail_runs_clean: agora #461 — `top` clears a value block whose tail is a block-local fresh copy of `vv`'s data
// The shape the fix must keep: a block whose tail lends nothing (agora #461).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #461: a function clearing a value block with a fresh tail
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ mk_copy ( Vec ( Vec String ) ) vv → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from `x` ) )
    ^ out
}

@ top ( Vec ( Vec String ) ) vv → v {
    ( clr { : ( Vec String ) t ( mk_copy vv ) t } )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] w 0 ) ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] w 0 ) 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
