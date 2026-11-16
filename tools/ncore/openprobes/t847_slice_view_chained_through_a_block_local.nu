// map: §7.6 | A2 | rejected | - | agora #847: `: ( Slice String ) e { : ( Vec String ) t … : ( Slice String ) w ( slice_from_vec t )  w }  ^ e`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f → ( Slice String ) {
    : ( Slice String ) e { : ~ ( Vec String ) t ( vec_new [String] ) ( vec_push [String] t ( string_from `an element long enough to live on the heap for sure` ) ) : ( Slice String ) w ( slice_from_vec [String] t ) w }
    ^ e
}

@ main → i { : ( Slice String ) r ( f ) ( nurl_println ( string_data ( slice_at [String] r 0 ) ) ) ^ 0 }
