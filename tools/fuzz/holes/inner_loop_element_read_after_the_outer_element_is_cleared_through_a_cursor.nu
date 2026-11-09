// inner_loop_element_read_after_the_outer_element_is_cleared_through_a_cursor: agora #482 — `~ r vv { : ~ cur r ~ x r { … } }`: the outer element's elements cleared through a cursor over it inside the inner loop; the inner element read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: an inner loop element read after the outer element is cleared through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    ~ r vv {
        : ~ ( Vec String ) cur r
        ~ x r {
            ( vec_clear [String] cur )
            ( nurl_println ( string_data x ) )
            break
        }
    }
    ^ 0
}
