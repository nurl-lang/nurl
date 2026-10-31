// vget_payload_returned_in_struct: agora #209 — the same as a returned struct's field, `^ @ Hold { e 1 }` (vget_payload_returned_in_struct).
// Closed: a `??` payload whose call lends out of a local of this frame (`mem_payload_local_lend`: the payload's `__pljk` / `__pljr`) is taken out of its `vec_get` slot, or copied where it lent, when it is handed back bare or as a returned literal's field; the function answers per call (agora #209).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | the same as a returned struct's field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Hold { String s i n }

@ first i n → Hold {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ?? ( vec_get [String] xs 0 ) { T e → { ^ @ Hold { e 1 } } F → {} }
    ^ @ Hold { ( string_from `none` ) 0 }
}

@ main → i {
    : Hold h ( first 1 )
    ( nurl_println_int ( string_len . h s ) )
    ^ 0
}
