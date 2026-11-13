// view_of_a_matched_payload_past_a_callee_growing_the_option: `?? o { T q → … ( w o ) … }`, a slice of q read after, w reserving through its own match of the option
// Closed: a `??` payload that is a cursor over the option handed (`cu_`) has its views ended by a callee that may grow or move that payload — the cursor's buffer is the option's payload's (agora #816).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #816: a view of a matched payload past a callee growing the option
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

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
            ( w o )
            ( nurl_println_int # i ( slice_at [u] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
