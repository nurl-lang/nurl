// inout_holder_given_a_view_copied_out_of_an_inout_struct_of_views_read_after_its_source_ended: `= w @ W { . src v }` in a callee, `src` an inout struct of views; w read after what src viewed ended
// Closed on main by 2026-11-15 (agora #583): the holder is tied to what the struct of views holds, not to the struct's own storage.
// main (github#1703 review): accepted (heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #583: a view copied out of an inout struct of views into an inout holder
$ `stdlib/core/string.nu`

: W { s v }
: V { s v i n }

@ f6 inout W w inout V src → v { = w @ W { . src v } }

@ main → i {
    : String b0 ( string_from `an outer string long enough for a heap buffer` )
    : ~ W w @ W { ( string_data b0 ) }
    {
        : String b ( string_from `an inner string long enough for a heap buffer` )
        : ~ V vv @ V { ( string_data b ) 1 }
        ( f6 w vv )
    }
    ( nurl_println . w v )
    ^ 0
}
