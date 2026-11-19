// literal_and_a_view_of_a_clone_handed_to_one_sink_runs_clean: AGORA-926 guard — `( use2 @ S { ( vec_clone [i] b ) 0 } sv )` - a literal of a clone and a view of the original handed to one sink: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-926 guard: `( use2 @ S { ( vec_clone [i] b ) 0 } sv )` - a literal of a clone and a view of the original handed to one sink: accepted
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Vec i ) buf i n }

@ use2 sink S x ( Slice i ) v → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] v 1 ) )
}

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Slice i ) sv ( slice_from_vec [i] b )
    ( use2 @ S { ( vec_clone [i] b ) 0 } sv )
    ^ 0
}
