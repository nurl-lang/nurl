// vget_payload_returned_bare: agora #209 — `?? ( vec_get [String] xs 0 ) { T e → { ^ e } … }`, xs a local: the caller got a String xs freed on the way out (vget_payload_returned_bare).
// Closed: a `??` payload whose call lends out of a local of this frame (`mem_payload_local_lend`: the payload's `__pljk` / `__pljr`) is taken out of its `vec_get` slot, or copied where it lent, when it is handed back bare or as a returned literal's field; the function answers per call (agora #209).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #209: a `vec_get` payload of a local Vec handed back bare: freed with the Vec on the way out
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first i n → String {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ?? ( vec_get [String] xs 0 ) { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( first 1 )
    ( nurl_println_int ( string_len s ) )
    ^ 0
}
