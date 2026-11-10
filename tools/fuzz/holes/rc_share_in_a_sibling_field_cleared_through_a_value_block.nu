// rc_share_in_a_sibling_field_cleared_through_a_value_block: the same through `{ ( rc_get . h a ) }`.
// Guard (claude-formal's #1679 review): a row swept for one field path still ends the borrows of a sibling field holding another share of the same `( Rc T )` value — the same-Rc rule fires for a path-precise row that did not reach the sibling, as for another binding.
// map: §6.5 | A2 | rejected | - | formal #1679 review: an Rc share in a sibling field cleared through a value block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) z }
: RR { R a i k }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v ( mks t ) ) ^ v }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ( Rc ( Vec S ) ) ra ( rc_new [( Vec S )] ( mkv `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec S ) ) rb ( rc_clone [( Vec S )] ra )
    : ~ R h @ R { ra rb }
    : S e ( vec_at [S] ( rc_get [( Vec S )] . h z ) 0 )
    : String f . e name
    ( vec_clear [S] { ( rc_get [( Vec S )] . h a ) } )
    ( nurl_println ( string_data f ) )
    ^ 0
}
