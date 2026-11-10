// value_block_of_a_parameters_field_handed_to_a_sink: `@ f H p → i { ^ ( eat { . p a } ) }`; the caller reads `. h a` after.
// Closed: a `sink` argument that only lends — a join whose arms are field reads or views (no ownership published, no binding selected), or a value block whose tail is a binding of an outer scope or a field of one (`__blk_arg_lends`: the tail's storage, read inside the block, is what its name names after it) — is handed a copy, as a join of names is (agora #555).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #555: a value block of a parameter's field handed to a sink
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

@ f H p → i { ^ ( eat { . p a } ) }

@ main → i {
    : ~ H h ( mkh )
    ( nurl_println_int ( f h ) )
    ( nurl_println_int # i ( vec_len [S] . h a ) )
    ^ 0
}
