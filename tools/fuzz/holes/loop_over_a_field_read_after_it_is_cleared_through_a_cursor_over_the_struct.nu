// loop_over_a_field_read_after_it_is_cleared_through_a_cursor_over_the_struct: agora #482 — `~ x . h items`; `hc`, a cursor over the whole struct `h`; `( vec_clear . hc items )` in the body; `x` read after
// Closed: a loop over a path is filed under that path, and a borrow of a binding that holds the path ends it (`feoallp`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field read after it is cleared through a cursor over the struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ main → i {
    : ~ H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `a string long enough for a heap buffer here` ) )
    : ~ H hc h
    ~ x . h items {
        ( vec_clear [String] . hc items )
        ( nurl_println ( string_data x ) )
        break
    }
    ^ 0
}
