// loop_over_a_nested_field_read_after_it_is_cleared_through_a_cursor_over_its_parent: agora #482 — `~ x . . h inner items`; `ic`, a cursor over `. h inner`; `( vec_clear . ic items )` in the body; `x` read after
// Closed: a loop over a path is filed under that path, and a borrow of a binding that holds the path ends it (`feoallp`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a nested field read after it is cleared through a cursor over its parent
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: I { ( Vec String ) items i n }
: H { I inner i m }

@ main → i {
    : ~ H h @ H { @ I { ( vec_new [String] ) 0 } 0 }
    ( vec_push [String] . . h inner items ( string_from `a string long enough for a heap buffer here` ) )
    : ~ I ic . h inner
    ~ x . . h inner items {
        ( vec_clear [String] . ic items )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}
