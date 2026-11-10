// element_lent_out_of_a_slice_field_viewing_its_sibling_then_the_sibling_cleared_is_refused: `= . h z ( slice_from_vec [S] . h a )`, `: S e ( slice_at [S] . h z 0 )`, `: String f . e name`, then `( vec_clear [S] . h a )` and a read of f
// Closed: a view field of a binding handed to a callee that lends it is a `pendvf` row: the bound result borrows what the field views (agora #566).
// main a403b200: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #566: `= . h z ( slice_from_vec [S] . h a )`, `: S e ( slice_at [S] . h z 0 )`, `: String f . e name`, then `( vec_clear [S] . h a )` and a read of f
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: V { ( Vec S ) a ( Slice S ) z }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ main → i {
    : ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ V h @ V { va ( slice_empty [S] ) }
    = . h z ( slice_from_vec [S] . h a )
    : S e ( slice_at [S] . h z 0 )
    : String f . e name
    ( vec_clear [S] . h a )
    ( nurl_println ( string_data f ) )
    ^ 0
}
