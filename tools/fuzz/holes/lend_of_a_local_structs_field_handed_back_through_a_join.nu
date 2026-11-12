// lend_of_a_local_structs_field_handed_back_through_a_join: agora #749 — `: H h …  ^ ? c ( f0 . h a ) ( fresh )`: a join arm's call over a field path of a local struct
// Closed: an arm of a returned join whose call is handed a field path is asked about the struct the field belongs to (mem_join_local_lend, __roots_have_field; agora #749).
// main 3a71bef7: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #749: `: H h …  ^ ? c ( f0 . h a ) ( fresh )`: a join arm's call over a field path of a local struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { String a ( Vec String ) items ? String o i n }
: W { H in i n }

@ f0 String p → String { ^ p }

@ idg [A] A p → A { ^ p }

@ mkh s t → H {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from t ) )
    ^ @ H { ( string_from t ) v @ ?String { T ( string_from t ) } 1 }
}

@ g b c → String {
    : H h ( mkh `a string long enough to live on the heap for sure` )
    ^ ? c ( f0 . h a ) ( string_from `fresh one, long enough for the heap, really` )
}

@ run b c → v {
    : String s ( g c )
    ( nurl_println ( string_data s ) )
}

@ main → i { ( run T ) ( run F ) ^ 0 }
