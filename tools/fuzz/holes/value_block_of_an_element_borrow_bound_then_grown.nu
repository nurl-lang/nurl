// value_block_of_an_element_borrow_bound_then_grown: `: ( Vec u ) j { e0 }` over `e0`, a `vec_at` element of `vv`, then `( vec_reserve [u] j 4096 )` while `sl`, a slice of `e0`, is still read.
// Closed: the borrow bound to the block begins from its tail `e0`, the source expression its row carries, so it is a borrow of `vv`'s element, and growing it ends the views into that element (agora #499). `: j e0` and `( vec_reserve [u] e0 4096 )` were refused already.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #499: a value block whose tail is an element borrow, bound and grown under a slice of the element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] vv inner )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    : ( Vec u ) j { e0 }
    ( vec_reserve [u] j 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
