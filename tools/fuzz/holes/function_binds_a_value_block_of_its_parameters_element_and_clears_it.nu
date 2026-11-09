// function_binds_a_value_block_of_its_parameters_element_and_clears_it: agora #461 — in `top`, `: r { : t ( vec_at p 0 ) t }`, then `( clr r )`
// Closed: a local bound to a value block that may lend is read out of what its source expression names (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function binds a value block of its parameter's element and clears it
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v {
    ( vec_clear [String] v )
}

@ top ( Vec ( Vec String ) ) p → v {
    : ( Vec String ) r { : ( Vec String ) t ( vec_at [( Vec String )] p 0 ) t }
    ( clr r )
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
