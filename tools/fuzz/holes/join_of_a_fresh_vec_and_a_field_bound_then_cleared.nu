// join_of_a_fresh_vec_and_a_field_bound_then_cleared: `: ( Vec S ) j ? != c 1 ( vec_new [S] ) . h a` owns its value on one path and is lent `. h a` on the other; `( vec_clear [S] j )` then clears `. h a` under a live borrow of its element.
// Closed: on the paths it is lent, the binding is a copy of the handle the arm hands on; its borrow row carries the join's source expression alone (bck_note_borrow's `sx`), so the clear ends the borrows of `. h a` (agora #360).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A1 | rejected | - | agora #360: a join of a fresh Vec and a field path, owned on one path and lent on the other, cleared through the binding
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
    : ( Vec S ) j ? != c 1 ( vec_new [S] ) . h a
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
