// literal_of_two_owners_handed_to_a_growing_sink_runs_clean: AGORA-926 guard — `( use @ P { a b } )` - a literal of two separate owners handed to a sink that grows one: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-926 guard: `( use @ P { a b } )` - a literal of two separate owners handed to a sink that grows one: accepted
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: P { ( Vec i ) a ( Vec i ) b }

@ use sink P x → v {
    : ~ P y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y a k ) = k + k 1 }
    ( nurl_println_int + ( vec_len [i] . y a ) ( vec_len [i] . y b ) )
}

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 2 )
    ( use @ P { a b } )
    ^ 0
}
