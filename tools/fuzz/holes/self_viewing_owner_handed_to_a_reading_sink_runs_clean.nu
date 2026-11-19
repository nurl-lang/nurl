// self_viewing_owner_handed_to_a_reading_sink_runs_clean: `: S x ( mk )` handed to a `sink` callee that only reads the view
// Closed: only a callee whose summary changes what the viewed field holds refuses the call (agora #606): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.4 | A2 | runs-clean | - | agora #606: x from mk handed to a sink callee that only reads the view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf ( Slice i ) v }

@ mk → S {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ~ S o @ S { b ( slice_empty [i] ) }
    = . o v ( slice_from_vec [i] . o buf )
    ^ o
}

@ eat sink S y → v {
    : ~ S z y
    ( nurl_println_int ( slice_at [i] . z v 1 ) )
}

@ main → i {
    : S x ( mk )
    ( eat x )
    ^ 0
}
