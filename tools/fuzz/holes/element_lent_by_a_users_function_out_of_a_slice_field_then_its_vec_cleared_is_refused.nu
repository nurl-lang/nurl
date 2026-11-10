// element_lent_by_a_users_function_out_of_a_slice_field_then_its_vec_cleared_is_refused: `: S e ( firsts . h z )`, firsts handing back `( slice_at [S] z 0 )` of its Slice parameter, then va cleared and e read
// Closed: a view field of a binding handed to a callee that lends it is a `pendvf` row: the bound result borrows what the field views (agora #566).
// main a403b200: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #566: `: S e ( firsts . h z )`, firsts handing back `( slice_at [S] z 0 )` of its Slice parameter, then va cleared and e read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: V { ( Vec S ) a ( Slice S ) z }
: ZH { ( Slice S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ firsts ( Slice S ) z → S { ^ ( slice_at [S] z 0 ) }

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ ZH h @ ZH { ( slice_from_vec [S] va ) }
    : S e ( firsts . h z )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
