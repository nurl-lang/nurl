// payload_slice_bound_out_of_its_arm_read_while_the_option_lives_runs_clean: `: ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → … }` over a local option, v read while o is unchanged
// AGORA-842 guard: accepted - the view points into o's payload, which lives
// map: §2.10 | A2 | runs-clean | - | AGORA-842
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ( Vec i ) ys ( vec_new [i] )
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    : ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] ys ) }
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
