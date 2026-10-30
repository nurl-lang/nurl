// outer_binding_borrows_an_inner_field: a binding of an outer block given a field that cannot be copied out of a struct an inner block declares (`= a . p c`) went on borrowing it after the inner block dropped the struct, fields and all.
// Closed: such a field cannot move out (a `% Drop` value leaves nothing in its place), so the assignment is rejected where its struct's block ends before the binding's (__nc_outlive_die); a handle field moves out instead (mem_udrop_field_move).
// v0.78.0: accepted; ASan reported heap-use-after-free reading the binding.
// map: §7.6 | A2 | rejected | h328 | an outer binding assigned a %Drop field with no clone out of a struct an inner block declares went on borrowing it after the block dropped the struct; rejected where the struct's block ends first
$ `stdlib/core/string.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: Plain {
    Conn c
    i n
}

@ main → i {
    : Plain keep @ Plain { @ Conn { ( string_from `k` ) } 0 }
    : ~ Conn a . keep c
    ? T {
        : Plain p @ Plain { @ Conn { ( string_from `x` ) } 1 }
        = a . p c
    } {}
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
