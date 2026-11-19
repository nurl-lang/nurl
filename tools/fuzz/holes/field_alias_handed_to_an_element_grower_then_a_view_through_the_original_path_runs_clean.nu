// field_alias_handed_to_an_element_grower_then_a_view_through_the_original_path_runs_clean: `: I ii . ww inner` handed to a grower, then a slice taken through `. . ww inner rows`
// AGORA-789 guard: accepted - the view sees the moved buffer
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
    ( top ii )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . . ww inner rows 0 ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
