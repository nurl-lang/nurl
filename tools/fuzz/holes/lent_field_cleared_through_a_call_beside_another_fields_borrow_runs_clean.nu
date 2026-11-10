// lent_field_cleared_through_a_call_beside_another_fields_borrow_runs_clean: agora #360 guard — `( vec_clear [S] ( idv . h a ) )` while `f` borrows from an element of another field, `. h z`.
// Guard: a row named by a source expression whose storage is a field path is swept for that path, as a `pendfield` row is: clearing what `idv` lends of `. h a` ends no borrow of `. h z`. Refused on main b997834, which swept it as all of `h`.
// main: refused (safe).
// map: §2.5 | A1 | runs-clean | - | agora #360 guard: a lent field cleared through a call beside a borrow of another field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) z }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vz ( vec_new [S] )
    ( vec_push [S] vz @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vz }
    : S e ( vec_at [S] . h z 0 )
    : String f . e name
    ( vec_clear [S] ( idv . h a ) )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
