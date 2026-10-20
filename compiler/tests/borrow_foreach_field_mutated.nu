// borrow_foreach_field_mutated.nu — iterating a field borrows that field
// for the loop body.
//
// `~ it . b items { … }` walks `b.items`' buffer; a push onto it inside
// the body may move that buffer under the loop, and so may handing `b`
// on whole to something that mutates it. Another field of `b` is free
// (foreach_field_path.nu).

$ `stdlib/core/vec.nu`

: Bag {
    ( Vec i ) items
    ( Vec i ) extra
}

@ main → i {
    : Bag b @ Bag { ( vec_new [i] ) ( vec_new [i] ) }
    ( vec_push [i] . b items 1 )
    ~ it . b items { ( vec_push [i] . b items + it 1 ) }
    ^ ( vec_len [i] . b items )
}
