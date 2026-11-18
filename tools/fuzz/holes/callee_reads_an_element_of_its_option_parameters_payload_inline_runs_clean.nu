// callee_reads_an_element_of_its_option_parameters_payload_inline_runs_clean: as t842_callee_grows_an_element_of_its_option_parameters_payload_inline, g only reads the element's length
// AGORA-842 guard: accepted - reading moves no buffer
// map: §2.10 | A2 | runs-clean | - | AGORA-842
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g ? ( Vec ( Vec i ) ) p → v {
    ?? p { T q → { ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] q 0 ) ) ) } F → {} }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv xs )
    : ~ ? ( Vec ( Vec i ) ) o @ ?( Vec ( Vec i ) ) { T vv }
    ?? o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] ( vec_at [( Vec i )] q 0 ) )
            ( g o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
