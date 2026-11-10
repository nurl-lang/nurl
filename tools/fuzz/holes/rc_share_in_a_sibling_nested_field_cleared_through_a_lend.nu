// rc_share_in_a_sibling_nested_field_cleared_through_a_lend: the same one level down, `. . g a a` and `. . g a z`.
// Guard (claude-formal's #1679 review): a row swept for one field path still ends the borrows of a sibling field holding another share of the same `( Rc T )` value — the same-Rc rule fires for a path-precise row that did not reach the sibling, as for another binding.
// map: §6.5 | A2 | rejected | - | formal #1679 review: an Rc share in a sibling nested field cleared through a lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) z }
: RR { R a i k }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v ( mks t ) ) ^ v }

@ main → i {
    : ( Rc ( Vec S ) ) ra ( rc_new [( Vec S )] ( mkv `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec S ) ) rb ( rc_clone [( Vec S )] ra )
    : ~ RR g @ RR { @ R { ra rb } 0 }
    : S e ( vec_at [S] ( rc_get [( Vec S )] . . g a z ) 0 )
    : String f . e name
    ( vec_clear [S] ( rc_get [( Vec S )] . . g a a ) )
    ( nurl_println ( string_data f ) )
    ^ 0
}
