// self_viewing_struct_moved_into_a_reading_sink_through_a_literal_runs_clean: `( look @ P { o 0 } )`, `look` only reading the view
// Closed: only a change of the viewed field, after the move or inside a callee that changes it, is refused (agora #563): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #563: ( look @ P { o 0 } ), look only reading the view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }
: P { S s i n }

@ look sink P p → v { ( nurl_println_int ( slice_at [i] . . p s v 1 ) ) }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    ( look @ P { o 0 } )
    ^ 0
}
