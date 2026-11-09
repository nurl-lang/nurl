// closure_over_a_field_of_a_lent_struct_run_after_its_vec_is_cleared: agora #483 — a closure over a field borrow of a lent struct (`: String n . q name`, `q = ( vec_at ps 0 )`), run after `ps` was cleared
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a field of a lent struct run after its Vec is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( string_from `a name cleared with its vector while the closure holds its handle` ) 1 } )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : P q ( vec_at [P] ps 0 )
        : String n . q name
        = f \ → i { ^ ( strlen ( string_data n ) ) }
    }
    ( vec_clear [P] ps )
    ( nurl_println_int ( f ) )
    ^ 0
}
