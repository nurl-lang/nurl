// slice_of_a_vec_at_binding_lent_back:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #762.
// map: §7.6 | A2 | runs-clean | - | agora #762: `: e0 ( vec_at vv 0 )  ^ ( slice_at ( slice_from_vec e0 ) 0 )`, vv a local Vec of Vecs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g → String {
    : ~ ( Vec String ) row ( vec_new [String] )
    ( vec_push [String] row ( string_from `an element long enough to live on the heap for sure` ) )
    : ~ ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv row )
    : ( Vec String ) e0 ( vec_at [( Vec String )] vv 0 )
    ^ ( slice_at [String] ( slice_from_vec [String] e0 ) 0 )
}

@ main → i { : String r ( g ) ( nurl_println ( string_data r ) ) ^ 0 }
