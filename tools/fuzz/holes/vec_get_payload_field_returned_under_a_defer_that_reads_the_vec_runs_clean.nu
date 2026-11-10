// vec_get_payload_field_returned_under_a_defer_that_reads_the_vec_runs_clean: agora #561 — `^ . p s` of a `vec_get` payload of a local Vec of structs, under a defer that reads the Vec: the field is copied, so the Vec's drop after the chain frees only its own
// main 6bafcaa1: the field was left lent under a defer, the Vec's drop freed it, and the caller read freed memory (heap-use-after-free).
// map: §2.10 | A2 | runs-clean | - | agora #561: `^ . p s` of a `vec_get` payload of a local Vec of structs, under a defer that reads the Vec: the field is copied, so the Vec's drop after the chain frees only its own
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: P { String s i n }

@ first → String {
    : ( Vec P ) vs ( vec_new [P] )
    ( vec_push [P] vs @ P { ( string_from `abc` ) 1 } )
    ; { ( nurl_println_int ( vec_len [P] vs ) ) }
    ?? ( vec_get [P] vs 0 ) { T p → { ^ . p s } F → { ^ ( string_new ) } }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
