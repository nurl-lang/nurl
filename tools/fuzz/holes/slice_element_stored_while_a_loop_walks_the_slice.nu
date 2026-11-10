// slice_element_stored_while_a_loop_walks_the_slice: agora #545 — `~ x a { = . a 0 … }`, a a slice that owns its elements: the store drops the element it replaces, which is the one the loop may be reading.
// Closed: refused when the slice owns its elements, as `vec_put` on the Vec a loop walks is; a slice of plain data is unaffected.
// main (before this PR): accepted; AddressSanitizer, heap-use-after-free on `x`.
// map: §2.5 | A2 | rejected | - | agora #545: a store into an element of the slice a loop walks released the element the loop was reading (UAF)
$ `stdlib/core/string.nu`

@ main → i {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, a0` ) ( string_from `a long enough string to be on the heap, a1` )]
    ~ x a {
        = . a 0 ( string_from `a long enough string to be on the heap, new` )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
