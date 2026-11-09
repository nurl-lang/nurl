// value_block_ending_in_a_lend_as_a_holder_kept_past_its_source: agora #391 — `( f 1 { : t ( vec_at vv 0 ) t } src )`, a value block as the holder
// Closed: a holder argument lent out of a binding is named by its source expression (`@sx`), so the callee's store lands on the owners that expression is a part of (agora #391).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: a value block ending in a lend as a holder kept past its source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ? T {
        : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( f 1 { : ( Vec s ) t ( vec_at [( Vec s )] vv 0 ) t } src )
    } {}
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
