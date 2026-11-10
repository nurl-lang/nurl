// join_of_two_fields_handed_to_a_sink: `( eat ? == c 1 . h a . h b )`.
// Closed: a `sink` argument that only lends — a join whose arms are field reads or views (no ownership published, no binding selected), or a value block whose tail is a binding of an outer scope or a field of one (`__blk_arg_lends`: the tail's storage, read inside the block, is what its name names after it) — is handed a copy, as a join of names is (agora #555).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #555: a join of two fields handed to a sink
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
    : i c ( vec_len [S] . h a )
    ( nurl_println_int ( eat ? == c 1 . h a . h b ) )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
