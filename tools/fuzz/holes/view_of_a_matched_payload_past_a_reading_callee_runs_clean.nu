// view_of_a_matched_payload_past_a_reading_callee_runs_clean: `?? o { T q → … ( w o ) … }` with w only reading the payload, a slice of q read after
// Kept: a callee that only reads the option's payload leaves the views of a payload cursor valid (agora #816).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #816: a view of a matched payload past a callee that reads it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ w ? ( Vec u ) o → v {
    ?? o { T p → ( nurl_println_int # i ( vec_len [u] p ) ) F → {} }
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ?( Vec u ) o @ ?( Vec u ) { T xs }
    ?? o {
        T q → {
            : ( Slice u ) sl ( slice_from_vec [u] q )
            ( w o )
            ( nurl_println_int # i ( slice_at [u] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
