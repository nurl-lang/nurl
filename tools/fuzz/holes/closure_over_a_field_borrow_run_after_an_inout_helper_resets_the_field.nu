// closure_over_a_field_borrow_run_after_an_inout_helper_resets_the_field: agora #483 — `n = . p name`, a field borrow of an owned struct; `f` a closure over `n`; `( reset . p name )` gives the field a new value through an `inout` parameter; `f` run
// Closed: a borrow whose bytes are its owner's own is a copy of that owner's handle, `~R`, which a field replaced ends (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a field borrow run after an inout helper resets the field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ reset inout String s → v { = s ( string_from `a second name, long enough for the heap too` ) }

@ main → i {
    : ~ P p @ P { ( string_from `the first name, long enough for the heap` ) 1 }
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String n . p name
        = f \ → i { ^ ( strlen ( string_data n ) ) }
    }
    ( reset . p name )
    ( nurl_println_int ( f ) )
    ^ 0
}
