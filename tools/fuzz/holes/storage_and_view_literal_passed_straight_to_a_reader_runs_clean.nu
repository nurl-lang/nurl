// storage_and_view_literal_passed_straight_to_a_reader_runs_clean: `( show @ S { sv b } )`, `show` only reading the view
// Closed: only a change of the viewed field, after the move or inside a callee that changes it, is refused (agora #563): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #563: ( show @ S { sv b } ), show only reading the view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Slice i ) v ( Vec i ) buf }

@ show S x → v { ( nurl_println_int ( slice_at [i] . x v 1 ) ) }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Slice i ) sv ( slice_from_vec [i] b )
    ( show @ S { sv b } )
    ^ 0
}
