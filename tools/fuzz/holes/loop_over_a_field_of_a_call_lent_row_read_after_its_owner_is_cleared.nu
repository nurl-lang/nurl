// loop_over_a_field_of_a_call_lent_row_read_after_its_owner_is_cleared: agora #482 — `~ x . ( vec_at bs 0 ) items`; `bs` cleared by name in the body; `x` read after
// Closed: the owners of a container a call lends are made sources the borrow sweep visits, so their end ends the element (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop over a field of a call-lent row, its owner cleared by name
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec String ) items i n }

@ main → i {
    : ( Vec B ) bs ( vec_new [B] )
    : B b0 @ B { ( vec_new [String] ) 0 }
    ( vec_push [String] . b0 items ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [B] bs b0 )
    ~ x . ( vec_at [B] bs 0 ) items {
        ( vec_clear [B] bs )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
