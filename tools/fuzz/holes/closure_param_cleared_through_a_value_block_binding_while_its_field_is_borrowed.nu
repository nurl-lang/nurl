// closure_param_cleared_through_a_value_block_binding_while_its_field_is_borrowed: the same with the binding made of a value block, `: ( Vec S ) j { v }` (agora #570).
// Closed: a closure parameter's derivations are in its literal's summary: a change through a local holding it ends the caller's borrows of the argument (github#1816, agora #770).
// main (before github#1816): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #570: a closure parameter cleared through a block binding under a caller borrow (UAF before #1816)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b ( Vec S ) z }

@ mkh → H {
    : ~ ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a heap string long enough for the heap buffer` ) 1 } )
    ^ @ H { a ( vec_new [S] ) ( vec_new [S] ) }
}

@ main → i {
    : ~ H h ( mkh )
    : ( @ v ( Vec S ) ) w \ ( Vec S ) v → v { : ( Vec S ) j { v } ( vec_clear [S] j ) }
    : S e ( vec_at [S] . h a 0 )
    ( w . h a )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
