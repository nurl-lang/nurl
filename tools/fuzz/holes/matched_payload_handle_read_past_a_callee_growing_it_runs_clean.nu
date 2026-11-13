// matched_payload_handle_read_past_a_callee_growing_it_runs_clean: `?? o { T q → … ( w o ) ( vec_len q ) }`: the payload cursor's handle read after the growth, its view read before
// Kept: the cursor's handle still reaches the grown payload — only views of its buffer end (agora #816).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #816: a payload handle read past a callee growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ w ? ( Vec u ) o → v {
    ?? o { T p → ( vec_reserve [u] p 4096 ) F → {} }
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ?( Vec u ) o @ ?( Vec u ) { T xs }
    ?? o {
        T q → {
            : ( Slice u ) sl ( slice_from_vec [u] q )
            ( nurl_println_int # i ( slice_at [u] sl 0 ) )
            ( w o )
            ( nurl_println_int # i ( vec_len [u] q ) )
        }
        F → {}
    }
    ^ 0
}
