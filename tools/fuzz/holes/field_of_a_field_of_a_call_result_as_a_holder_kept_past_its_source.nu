// field_of_a_field_of_a_call_result_as_a_holder_kept_past_its_source: agora #391 — `( f 1 . . ( vec_at os 0 ) inner out src )`, a field path of a call's result as the holder
// Closed: a holder argument lent out of a binding is named by its source expression (`@sx`), so the callee's store lands on the owners that expression is a part of (agora #391).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: a field of a field of a call result as a holder kept past its source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: I { ( Vec s ) out }
: O { I inner }

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ( Vec O ) os ( vec_new [O] )
    ( vec_push [O] os @ O { @ I { ( vec_new [s] ) } } )
    ? T {
        : String src ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( f 1 . . ( vec_at [O] os 0 ) inner out src )
    } {}
    ( nurl_println ( vec_at [s] . . ( vec_at [O] os 0 ) inner out 0 ) )
    ^ 0
}
