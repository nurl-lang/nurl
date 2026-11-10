// value_block_of_a_binding_handed_to_a_sink_then_read: `( eat { w } )`, w a local Vec read after.
// Closed: a `sink` argument that only lends — a join whose arms are field reads or views (no ownership published, no binding selected), or a value block whose tail is a binding of an outer scope or a field of one (`__blk_arg_lends`: the tail's storage, read inside the block, is what its name names after it) — is handed a copy, as a join of names is (agora #555).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #555: a value block of a binding handed to a sink, the binding read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: G { H x i k }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vb ( vec_new [S] )
    ( vec_push [S] vb @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vb }
    : String f ( string_from `ok` )
    : ( Vec S ) w ( vec_new [S] )
    ( vec_push [S] w @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    ( nurl_println_int ( eat { w } ) )
    ( nurl_println_int # i ( vec_len [S] w ) )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
