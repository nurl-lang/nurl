// map: §2.10 | A2 | rejected | - | agora #789: `: I ii . ww inner` handed to a grower of `( vec_at . i rows 0 )`, past a slice taken through `. . ww inner rows`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: I { ( Vec ( Vec u ) ) rows }

: W { I inner }

@ top I i → v { ( vec_reserve [u] ( vec_at [( Vec u )] . i rows 0 ) 4096 ) }

@ main → i {
    : ( Vec ( Vec u ) ) w0 ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w0 a )
    : W ww @ W { @ I { w0 } }
    : I ii . ww inner
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . . ww inner rows 0 ) )
    ( top ii )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
