// option_and_a_slice_of_its_payload_handed_to_one_reading_call_runs_clean: as t842_option_and_a_slice_of_its_payload_handed_to_one_growing_call, wr only reads o's payload
// AGORA-842 guard: accepted - a call that grows nothing may see both
// map: §2.10 | A2 | runs-clean | - | AGORA-842
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ wr ? ( Vec i ) o ( Slice i ) sl → v {
    ?? o { T q → ( nurl_println_int ( vec_len [i] q ) ) F → {} }
    ( nurl_println_int ( slice_at [i] sl 1 ) )
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    ?? o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( wr o sl )
        }
        F → {}
    }
    ^ 0
}
