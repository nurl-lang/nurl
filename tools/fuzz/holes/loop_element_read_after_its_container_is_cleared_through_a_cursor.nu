// loop_element_read_after_its_container_is_cleared_through_a_cursor: agora #482 — `~ x t` over an owned `t`; `cur`, a cursor over `t`, cleared in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after its container is cleared through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : ~ ( Vec String ) cur t
    ~ x t {
        ( vec_clear [String] cur )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
