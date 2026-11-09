// payload_join_as_a_holder_argument_kept_past_its_source: agora #391 — `( f 1 ?? ( vec_get vv 0 ) { T e → e F → ( vec_at vv 0 ) } src )`, a `??` join as the holder
// Closed: a holder argument lent out of a binding is named by its source expression (`@sx`), so the callee's store lands on the owners that expression is a part of (agora #391).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: a payload join as a holder argument kept past its source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    : ?( Vec ( Vec s ) ) ov ( vec_get [( Vec ( Vec s ) )] ( vec_new [( Vec ( Vec s ) )] ) 0 )
    ? T {
        : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( f 1 ?? ( vec_get [( Vec s )] vv 0 ) { T e → e F → ( vec_at [( Vec s )] vv 0 ) } src )
    } {}
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
