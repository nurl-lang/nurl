// view_handed_beside_an_element_lent_as_a_holder_kept_past_its_source: agora #391 — `( fv2 1 ( vec_at [( Vec s )] vv 0 ) ( string_data src ) )`, `fv2` pushing its view argument
// Closed: a holder argument lent out of a binding is named by its source expression (`@sx`), so the callee's store lands on the owners that expression is a part of (agora #391).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: a view handed beside an element lent as a holder, kept past its source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fv2 i k ( Vec s ) out s x → v { ( vec_push [s] out x ) }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ? T {
        : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( fv2 1 ( vec_at [( Vec s )] vv 0 ) ( string_data src ) )
    } {}
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
