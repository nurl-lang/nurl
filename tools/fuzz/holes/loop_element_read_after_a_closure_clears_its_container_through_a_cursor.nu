// loop_element_read_after_a_closure_clears_its_container_through_a_cursor: agora #482 — `~ x t` over an owned `t`; a closure over `cur`, a cursor over `t`, clears it when it runs in the body; `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after a closure clears its container through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : ~ ( Vec String ) cur t
    : ( @ v ) wipe \ → v { ( vec_clear [String] cur ) }
    ~ x t {
        ( wipe )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
