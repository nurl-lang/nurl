// self_viewing_struct_pushed_read_in_place_runs_clean: `o`, viewing its own `buf`, pushed into a Vec and its view read in place through `vec_at`
// Closed: only a change of the viewed field, after the move or inside a callee that changes it, is refused (agora #563): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #563: o pushed into a Vec and its view read in place through vec_at
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Vec i ) e ( vec_new [i] )
    : ~ S o @ S { b ( slice_from_vec [i] e ) }
    = . o v ( slice_from_vec [i] . o buf )
    : ~ ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs o )
    ( nurl_println_int ( slice_at [i] . ( vec_at [S] vs 0 ) v 1 ) )
    ^ 0
}
