// field_alias_handed_to_an_element_grower_past_a_view_of_a_sibling_field_runs_clean: `: I ii . ww inner` handed to a grower of `( vec_at . i rows 0 )`, past a slice taken through `. . ww other rows`
// AGORA-789 guard: accepted - the growth is under ww.inner, which ww.other does not hold
// map: §2.10 | A2 | runs-clean | - | AGORA-789
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: I { ( Vec ( Vec u ) ) rows }

: W { I inner I other }

@ top I i → v { ( vec_reserve [u] ( vec_at [( Vec u )] . i rows 0 ) 4096 ) }

@ peek I i → i { ^ # i ( vec_len [( Vec u )] . i rows ) }

@ main → i {
    : ( Vec ( Vec u ) ) w0 ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w0 a )
    : ( Vec ( Vec u ) ) w1 ( vec_new [( Vec u )] )
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b 8 )
    ( vec_push [( Vec u )] w1 b )
    : W ww @ W { @ I { w0 } @ I { w1 } }
    : I ii . ww inner
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . . ww other rows 0 ) )
    ( top ii )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
