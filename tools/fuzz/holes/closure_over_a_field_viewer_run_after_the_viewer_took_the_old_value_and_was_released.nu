// closure_over_a_field_viewer_run_after_the_viewer_took_the_old_value_and_was_released: agora #483 — `n = . p name` inside a block, `f` over `n`; the field replaced while `n` lives (`n` takes the old value over); `n` released at its block's end; `f` run after
// Closed: the copies of a replaced field's handle are re-tied to the viewer that takes its value over (bck_fview_take, agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a field viewer run after the viewer took the old value and was released
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ~ P p @ P { ( string_from `the first name, long enough for the heap` ) 1 }
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String n . p name
        = f \ → i { ^ ( strlen ( string_data n ) ) }
        = . p name ( string_from `a second name, long enough for the heap too` )
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
