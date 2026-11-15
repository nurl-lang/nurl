// map: §7.6 | A2 | runs-clean | - | agora #762: `: ~ ( Slice String ) cur …  ?? ( slice_sub cur … ) { T s1 → = cur s1  ^ ( slice_at cur 0 ) }` over a local Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g → String {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element long enough to live on the heap for sure` ) )
    ( vec_push [String] v ( string_from `another element long enough to live on the heap` ) )
    : ~ ( Slice String ) cur ( slice_from_vec [String] v )
    ?? ( slice_sub [String] cur 1 2 ) { T s1 → { = cur s1 ^ ( slice_at [String] cur 0 ) } F → {} }
    ^ ( string_from `none` )
}

@ main → i { : String r ( g ) ( nurl_println ( string_data r ) ) ^ 0 }
