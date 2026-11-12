// vec_at_element_or_fresh_struct_handed_back_runs_clean: agora #625 — `@ g ( Vec S ) v b c → S { ? c { ^ ( vec_at [S] v 0 ) } {} ^ ( mks … ) }` bound and read, the Vec cleared after: the fresh S leaked
// Closed: a function whose returns hand back a lending call's result on one path and a value of its own on another answers per call (__hown_mixed); its fresh results are released by the caller (agora #625).
// main b64e33a1: accepted; LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #625: `@ g ( Vec S ) v b c → S { ? c { ^ ( vec_at [S] v 0 ) } {} ^ ( mks … ) }` bound and read, the Vec cleared after: the fresh S leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: S { String name i n }
: Q { ( Slice S ) z i k }
: ZH { ( Slice S ) z }
: QV { ( Vec S ) a i k }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ mkvv s t → ( Vec ( Vec S ) ) {
    : ( Vec ( Vec S ) ) v ( vec_new [( Vec S )] )
    ( vec_push [( Vec S )] v ( mkv t ) )
    ^ v
}

@ mkvs s t → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from t ) )
    ^ v
}

@ g ( Vec S ) v b c → S { ? c { ^ ( vec_at [S] v 0 ) } {} ^ ( mks `fresh from g, long enough for the heap buffer` ) }

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : S d ( mks `the default string, also long enough for the heap` )
    : S e ( g va F )
    ( nurl_println ( string_data . e name ) )
    ( vec_clear [S] va )
    ^ 0
}
