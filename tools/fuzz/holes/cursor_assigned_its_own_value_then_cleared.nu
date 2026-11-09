// cursor_assigned_its_own_value_then_cleared: `: ~ ( Vec S ) j . h a`, then `= j j`, then `( vec_clear [S] j )` while `f`, a field of an element of `. h a`, is still read.
// Closed: a binding given its own value gets no `assign` row — nothing about it changed — so it still borrows `. h a` and the clear ends `f` (agora #554). The row gave it a fresh value of its own and ended its borrow.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #554: a cursor assigned its own value, then cleared under an element borrow
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
    : ~ ( Vec S ) j . h a
    = j j
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
