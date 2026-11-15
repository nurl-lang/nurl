// inout_holder_given_a_view_copied_out_of_a_field_struct_of_views_read_after_its_source_ended: as …_out_of_an_inout_struct_of_views_…, the source a field `( f6 w . q vv )`
// Closed on main by 2026-11-15 (agora #583): the holder is tied to what the field's struct of views holds.
// main (github#1703 review): accepted (heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #583: a view copied out of a field struct of views into an inout holder
$ `stdlib/core/string.nu`

: W { s v }
: V { s v i n }
: Q { V vv }

@ f6 inout W w inout V src → v { = w @ W { . src v } }

@ main → i {
    : String b0 ( string_from `an outer string long enough for a heap buffer` )
    : ~ W w @ W { ( string_data b0 ) }
    {
        : String b ( string_from `an inner string long enough for a heap buffer` )
        : ~ Q q @ Q { @ V { ( string_data b ) 1 } }
        ( f6 w . q vv )
    }
    ( nurl_println . w v )
    ^ 0
}
