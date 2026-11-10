// value_block_of_a_block_local_handed_to_a_sink_runs_clean: agora #555 guard — `( eat { : ~ ( Vec S ) t … t } )`: a value block opens no scope, so its local lives on to the enclosing scope's end, which drops it; the block lends it, and the callee is handed a copy (no leak, no double free under ASan + LSan).
// Guard: a block's own local as its tail is lent like any other binding (agora #193); only a whole `inout` parameter is taken over, as the bare name is.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #555 guard: a value block of a block-local handed to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkh → H {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    ^ @ H { va ( vec_new [S] ) }
}

@ main → i {
    ( nurl_println_int ( eat { : ~ ( Vec S ) t ( vec_new [S] ) ( vec_push [S] t @ S { ( string_from `a block-local element long enough for the heap` ) 2 } ) t } ) )
    ^ 0
}
