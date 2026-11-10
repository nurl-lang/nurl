// value_block_of_a_parameters_field_returned_and_cleared_by_the_caller: `@ pick H h → ( Vec S ) { : ( Vec S ) j { . h a }  ^ j }`; the caller clears `( pick h )`'s result under an element borrow of `. h a`.
// Closed: a binding of a value block whose tail is a field read is that read (`: j { . h a }` is `: j . h a`, __blk_bind_tt): it keeps the field source the return summary reads, so `^ j` lends the parameter's field (agora #570).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #570: a bound value block of a parameter's field handed back, the result cleared by the caller
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

@ pick H h → ( Vec S ) {
    : ( Vec S ) j { . h a }
    ^ j
}

@ main → i {
    : ~ H h ( mkh )
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : ( Vec S ) r ( pick h )
    ( vec_clear [S] r )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
