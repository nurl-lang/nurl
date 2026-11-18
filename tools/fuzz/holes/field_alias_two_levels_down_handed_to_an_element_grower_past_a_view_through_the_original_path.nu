// field_alias_two_levels_down_handed_to_an_element_grower_past_a_view_through_the_original_path: `: I ii . . x w inner` handed to a grower of `( vec_at . i rows 0 )`, past a slice taken through `. . . x w inner rows`
// AGORA-789: refused - as alias_of_a_struct_field_handed_to_an_element_grower_view_through_the_path, a level deeper
// map: §2.10 | A2 | rejected | - | AGORA-789
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: I { ( Vec ( Vec u ) ) rows }

: W { I inner }

: X { W w }

@ top I i → v { ( vec_reserve [u] ( vec_at [( Vec u )] . i rows 0 ) 4096 ) }

@ main → i {
    : ( Vec ( Vec u ) ) w0 ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w0 a )
    : X x @ X { @ W { @ I { w0 } } }
    : I ii . . x w inner
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . . . x w inner rows 0 ) )
    ( top ii )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
