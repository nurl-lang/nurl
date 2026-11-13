// loop_over_a_matched_payload_past_a_callee_growing_an_element_runs_clean: `~ e q` over a Vec-of-Vec payload cursor, the body handing the option to a callee that grows only an element
// Kept: a callee moving only an element's buffer leaves the payload's own buffer, which the loop reads, where it is (agora #816's review).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #816: a loop over a matched payload past a callee growing an element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

@ wi ? ( Vec ( Vec u ) ) o → v {
    ?? o { T p → { : ( Vec u ) e ( vec_at [( Vec u )] p 0 ) ( vec_reserve [u] e 4096 ) } F → {} }
}

@ main → i {
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    : ( Vec ( Vec u ) ) xs ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] xs inner )
    ( vec_push [( Vec u )] xs ( vec_new [u] ) )
    : ?( Vec ( Vec u ) ) o @ ?( Vec ( Vec u ) ) { T xs }
    ?? o {
        T q → {
            ~ e q {
                ( wi o )
                ( nurl_println_int ( vec_len [u] e ) )
            }
        }
        F → {}
    }
    ^ 0
}
