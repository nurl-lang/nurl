// map: §7.6 | A2 | runs-clean | - | agora #762: `: H h ( vec_at [H] hs 0 )  ^ ( f0 . h a )`, hs a local Vec: a lend of an element's field handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String a i n }

@ f0 String p → String { ^ p }

@ g → String {
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { ( string_from `a string long enough to live on the heap for sure` ) 1 } )
    : H h ( vec_at [H] hs 0 )
    ^ ( f0 . h a )
}

@ main → i {
    : String s ( g )
    ( nurl_println ( string_data s ) )
    ^ 0
}
