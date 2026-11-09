// option_assigned_a_value_block_of_itself_read_after_its_source_cleared: `: ~ ?S o ( vec_get [S] . h a 0 )  = o { o }`, then `( vec_clear [S] . h a )` and the payload read.
// Closed: `= o { o }` is `o` given its own value, which leaves its borrow of `. h a` as it was; the clear ends it and the read is refused (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #554: an option assigned a value block of itself, read after its source was cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: V { s a i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ eats sink String s → i { ^ # i ( string_len s ) }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vb ( vec_new [S] )
    ( vec_push [S] vb @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vb }
    : i c ( vec_len [S] . h a )
    : ~ ? S o ( vec_get [S] . h a 0 )
    = o { o }
    ( vec_clear [S] . h a )
    ?? o { T x → { ( nurl_println_int ( string_len . x name ) ) } F → {} }
    ^ 0
}
