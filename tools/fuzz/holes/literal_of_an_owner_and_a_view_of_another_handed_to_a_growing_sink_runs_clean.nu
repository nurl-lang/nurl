// literal_of_an_owner_and_a_view_of_another_handed_to_a_growing_sink_runs_clean: AGORA-926 guard — `( use @ S { ( slice_from_vec [i] c ) b } )` - a literal of an owner and a view of another binding, handed to a sink that grows the owner: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-926 guard: `( use @ S { ( slice_from_vec [i] c ) b } )` - a literal of an owner and a view of another binding, handed to a sink that grows the owner: accepted
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Slice i ) v ( Vec i ) buf }

@ use sink S x → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . y v 1 ) )
}

@ main → i {
    : ( Vec i ) c ( vec_new [i] )
    ( vec_push [i] c 1 )
    ( vec_push [i] c 2 )
    : ( Vec i ) b ( vec_new [i] )
    ( use @ S { ( slice_from_vec [i] c ) b } )
    ( nurl_println_int ( vec_len [i] c ) )
    ^ 0
}
