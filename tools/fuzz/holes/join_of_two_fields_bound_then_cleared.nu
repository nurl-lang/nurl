// join_of_two_fields_bound_then_cleared: `: ( Vec S ) j ? == c 1 . h a . h b`, then `( vec_clear [S] j )` while `f`, a field of an element of `. h a`, is still read.
// Closed: a borrow bound to a join is a copy of the handle an arm hands on as it is; its row carries the join's source expression and the walk begins it from each arm's field path (bck_sx_hpaths), so the clear through `j` ends the borrows of `. h a` and `. h b` (agora #360). The arms' own reads went to the join's rows, so the borrow had no source at all.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #360: a join of two field paths, bound, cleared through the binding while an element borrow of one arm is live
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
    : ( Vec S ) j ? == c 1 . h a . h b
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
