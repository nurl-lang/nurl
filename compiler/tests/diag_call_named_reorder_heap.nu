// diag_call_named_reorder_heap.nu — a keyword call that names a
// heap-holding binding out of the declared order. The reordering path
// records none of the positional path's borrow rows, so such an argument
// is refused with the two spellings that are checked: the declared order
// by name, or positional (agora #434).
$ `stdlib/core/vec.nu`

@ clr2 i n ( Vec i ) v → i { ( vec_clear [i] v ) ^ n }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : i r ( clr2 v : v n : 0 )
    ^ r
}
