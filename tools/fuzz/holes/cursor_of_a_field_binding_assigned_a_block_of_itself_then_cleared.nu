// cursor_of_a_field_binding_assigned_a_block_of_itself_then_cleared: `: ( Vec S ) j0 . h a  : ~ ( Vec S ) j j0  = j { j }`, then `( vec_clear [S] j )` under an element borrow of `. h a`.
// Closed: as cursor_assigned_a_value_block_of_itself_then_cleared, through a copy of a field borrow (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #554: a cursor of a field binding assigned a value block of itself, then cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: G { H x i k }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vb ( vec_new [S] )
    ( vec_push [S] vb @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vb }
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    : ( Vec S ) j0 . h a
    : ~ ( Vec S ) j j0
    = j { j }
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
