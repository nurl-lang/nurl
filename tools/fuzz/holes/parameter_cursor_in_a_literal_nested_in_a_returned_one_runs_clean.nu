// parameter_cursor_in_a_literal_nested_in_a_returned_one_runs_clean: `: ~ cur v`, `^ @ W { @ H { cur 0 } }`, the caller growing v after
// Kept: a parameter cursor copied into a literal nested in a returned one lends the parameter on no run — the result owns its copy, and releases it (agora #824's review).
// main 83059aae: accepted; runs clean under AddressSanitizer and LeakSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #824: a parameter cursor in a literal nested in a returned one
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }
: W { H h }

@ mk ( Vec i ) v → W {
    : ~ ( Vec i ) cur v
    ^ @ W { @ H { cur 0 } }
}

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : W w ( mk t )
    ( vec_push [i] t 2 )
    ( nurl_println_int + ( vec_len [i] . . w h items ) ( vec_len [i] t ) )
    ^ 0
}
