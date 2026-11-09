// closure_capturing_a_field_borrow_kept_past_its_struct: agora #483 — a closure captures a field borrow (`: String n . p name`) and outlives the struct
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure capturing a field borrow kept past its struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : P p @ P { ( string_from `a name freed with its struct at the end of the block` ) 1 }
        : String n . p name
        = f \ → i { ^ ( strlen ( string_data n ) ) }
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
