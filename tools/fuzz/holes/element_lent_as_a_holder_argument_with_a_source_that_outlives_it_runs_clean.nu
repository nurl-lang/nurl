// element_lent_as_a_holder_argument_with_a_source_that_outlives_it_runs_clean: agora #391 — `( f 1 ( vec_at [( Vec s )] vv 0 ) src )`, `src` declared before `vv`, so it outlives it
// The shape the fix must keep: a source that outlives the holder's owner (agora #391).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #391: an element lent as a holder argument with a source that outlives it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ( f 1 ( vec_at [( Vec s )] vv 0 ) src )
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
