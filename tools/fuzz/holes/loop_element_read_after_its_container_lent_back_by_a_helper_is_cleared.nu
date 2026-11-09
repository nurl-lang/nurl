// loop_element_read_after_its_container_lent_back_by_a_helper_is_cleared: agora #482 — `~ x t`; `( vec_clear ( id t ) )`, `id` lending `t` back whole; `x` read after
// Closed: a row handing a call a value lent out of what a loop element is a part of reaches the borrow sweep, which ends the element (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after its container, lent back by a helper, is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec String ) q → ( Vec String ) { ^ q }

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ~ x t {
        ( vec_clear [String] ( id t ) )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}
