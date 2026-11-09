// loop_element_read_after_it_is_replaced_through_a_cursor: agora #482 — `~ x t` over an owned `t`; the element replaced by `vec_set` through `cur` in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after it is replaced through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : ~ ( Vec String ) cur t
    ~ x t {
        ( vec_set [String] cur 0 ( string_from `a replacement long enough for a heap buffer` ) )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
