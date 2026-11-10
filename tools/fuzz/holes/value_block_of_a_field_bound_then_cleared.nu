// value_block_of_a_field_bound_then_cleared: `: ( Vec S ) j { . h a }`, then `( vec_clear [S] j )` while a field of an element of `. h a` is still read.
// Closed: a borrow bound to a value block is a copy of the handle its tail hands on; its row carries the block's source expression, `h.a`, and the walk begins it there, as `: j . h a` does (agora #360, #499).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #499: a value block whose tail is a field path, bound, cleared through the binding under an element borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ~ H h @ H { va ( vec_new [S] ) }
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    : ( Vec S ) j { . h a }
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
