// loop_element_read_after_an_inner_loop_clears_its_container: agora #482 — `~ x t` over an owned `t`; an inner `~` loop over another Vec clears `t` through `cur` in its body; `x` read after the inner loop
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after an inner loop clears its container through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : ( Vec i ) ks ( vec_new [i] )
    ( vec_push [i] ks 1 )
    : ~ ( Vec String ) cur t
    ~ x t {
        ~ k ks { ( vec_clear [String] cur ) }
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
