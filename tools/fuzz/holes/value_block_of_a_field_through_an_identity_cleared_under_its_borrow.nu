// value_block_of_a_field_through_an_identity_cleared_under_its_borrow: `( vec_clear [S] ( idv { . h z } ) )` while `f` borrows from an element of `. h z` (agora #566, item 3).
// Closed: a value block whose tail is a binding or a field read counts as an argument that may lend (arg_lendy), so the forwarder's result is named by its source expression for the clear, as `( idv . h z )` is.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #566: a value block of a field through an identity function, cleared under its element borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) z }
: H { ( Vec S ) a ( Vec S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v ( mks t ) ) ^ v }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ~ H h @ H { ( mkv `a` ) ( mkv `an element string long enough for a heap buffer` ) }
    : S e ( vec_at [S] . h z 0 )
    : String f . e name
    ( vec_clear [S] ( idv { . h z } ) )
    ( nurl_println ( string_data f ) )
    ^ 0
}
