// owned_vec_assigned_a_nested_value_block_of_itself: `= v ? > c 0 v v  = v { { v } }`, then pushed and read.
// Closed: a value block whose tail is the binding itself is that binding given its own value, as `= v v` is (gen_assign reads it by its tail; a block whose tail is a block hands that tail up): nothing is released and the same buffer is not stored back (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #554: an owned Vec assigned a nested value block of itself
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: V { s a i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ eats sink String s → i { ^ # i ( string_len s ) }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vb ( vec_new [S] )
    ( vec_push [S] vb @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vb }
    : i c ( vec_len [S] . h a )
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `an element string long enough for a heap buffer` ) 3 } )
    = v ? > c 0 v v
    = v { { v } }
    ( vec_push [S] v @ S { ( string_from `two` ) 4 } )
    ( nurl_println_int ( vec_len [S] v ) )
    ^ 0
}
