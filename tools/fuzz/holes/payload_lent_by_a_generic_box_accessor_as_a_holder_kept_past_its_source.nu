// payload_lent_by_a_generic_box_accessor_as_a_holder_kept_past_its_source: agora #391 — `( f 1 ( inner [s] b ) src )`, a generic accessor over a Box as the holder
// Closed: a holder argument lent out of a binding is named by its source expression (`@sx`), so the callee's store lands on the owners that expression is a part of (agora #391).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: a payload lent by a generic box accessor as a holder kept past its source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ inner [T] ( Box ( Vec T ) ) b → ( Vec T ) {
    ^ ( box_get [( Vec T )] b )
}

@ main → i {
    : ( Box ( Vec s ) ) b ( box_new [( Vec s )] ( vec_new [s] ) )
    ? T {
        : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( f 1 ( inner [s] b ) src )
    } {}
    ( nurl_println ( vec_at [s] ( box_get [( Vec s )] b ) 0 ) )
    ^ 0
}
