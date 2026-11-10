// generic_callee_clearing_a_value_block_of_its_parameters_field: `@ wipe [T] inout ( P T ) p → v { : ( Vec T ) j { . p a }  ( vec_clear [T] j ) }`.
// Closed: a value block or a join whose value is one binding or field path derives from that name, as the bare spelling does (__pderiv_note), so the function's drop summary carries the clear through it to the parameter and the caller's element borrow ends at the call (agora #556).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #556: a generic callee clearing a value block of its parameter's field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b ( Vec S ) z }

@ mkh → H {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vz ( vec_new [S] )
    ( vec_push [S] vz @ S { ( string_from `another element string long enough for a heap buffer` ) 2 } )
    ^ @ H { va ( vec_new [S] ) vz }
}

: P [T] { ( Vec T ) a ( Vec T ) b }

@ wipe [T] inout ( P T ) p → v {
    : ( Vec T ) j { . p a }
    ( vec_clear [T] j )
}

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ~ ( P S ) p @ ( P S ) { va ( vec_new [S] ) }
    : S e ( vec_at [S] . p a 0 )
    : String f . e name
    ( wipe [S] p )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
