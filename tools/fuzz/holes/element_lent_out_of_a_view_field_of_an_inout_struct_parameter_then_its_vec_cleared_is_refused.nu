// element_lent_out_of_a_view_field_of_an_inout_struct_parameter_then_its_vec_cleared_is_refused: `@ fq inout Q q → S { ^ ( slice_at [S] . q z 0 ) }`, `: S e ( fq . h q )`, then the Vec `. q z` views cleared and e read
// Closed: an inout view field is a `pendvf` row and a call root by its path (gen_inout_field_addr sets no g_member_path) (agora #590's review).
// main 5aeddd16: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #590: a lend out of a view field of an inout struct parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: Q { ( Slice S ) z i k }
: H2 { Q q i m }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ fq inout Q q → S { ^ ( slice_at [S] . q z 0 ) }

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ H2 h @ H2 { @ Q { ( slice_from_vec [S] va ) 1 } 2 }
    : S e ( fq . h q )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
