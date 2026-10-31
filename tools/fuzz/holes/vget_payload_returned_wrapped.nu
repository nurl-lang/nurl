// vget_payload_returned_wrapped: agora #209 — the same rewrapped, `^ @ ?String { T e }` (agora #209's report) (vget_payload_returned_wrapped).
// Closed: a `??` payload whose call lends out of a local of this frame (`mem_payload_local_lend`: the payload's `__pljk` / `__pljr`) is taken out of its `vec_get` slot, or copied where it lent, when it is handed back bare or as a returned literal's field; the function answers per call (agora #209).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | the same rewrapped in a returned option
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first i n → ?String {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ?? ( vec_get [String] xs 0 ) { T e → { ^ @ ?String { T e } } F → {} }
    ^ @ ?String { F }
}

: Hold { String s i n }

@ main → i {
    ?? ( first 1 ) { T e → ( nurl_println_int ( string_len e ) ) F → ( nurl_println `none` ) }
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    : ~ i k 0
    ?? ( vec_get [String] xs 0 ) { T e → { : Hold h @ Hold { e 1 } = k ( string_len . h s ) } F → {} }
    ( nurl_println_int k )
    ?? ( vec_get [String] xs 0 ) { T e → ( nurl_println_int ( string_len e ) ) F → {} }
    ^ 0
}
