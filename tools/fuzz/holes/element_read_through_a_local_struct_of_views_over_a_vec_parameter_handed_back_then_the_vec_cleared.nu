// element_read_through_a_local_struct_of_views_over_a_vec_parameter_handed_back_then_the_vec_cleared: agora #590 — a function puts a Slice of its Vec parameter into a local struct and hands back an element read through that field; the caller clears the Vec, then reads the element
// Closed: a view field of a struct of views, and a local struct holding a view, are what an element read through them reaches; the function's lend names the parameter behind the view.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #590: a function puts a Slice of its Vec parameter into a local struct and hands back an element read through that field; the caller clears the Vec, then reads the element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: ZH { ( Slice S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ f ( Vec S ) va → S {
    : ZH h @ ZH { ( slice_from_vec [S] va ) }
    ^ ( slice_at [S] . h z 0 )
}

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : S e ( f va )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
