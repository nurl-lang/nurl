// element_lent_as_a_holder_argument_given_a_temporary_source: agora #391 — `( f 1 ( vec_at [( Vec s )] vv 0 ) ( string_from … ) )`, `f` pushing `( string_data src )`
// Closed: a holder named by its source expression is checked for a temporary source as a named holder is (bck_diag_vbuf_temp, agora #391).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #391: an element lent as a holder argument given a temporary source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i k ( Vec s ) out String src → v { ( vec_push [s] out ( string_data src ) ) }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ( f 1 ( vec_at [( Vec s )] vv 0 ) ( string_from `the first heap string, long enough to be on the heap for sure` ) )
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
