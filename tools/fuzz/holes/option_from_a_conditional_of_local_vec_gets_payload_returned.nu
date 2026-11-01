// option_from_a_conditional_of_local_vec_gets_payload_returned: agora #300 — (e) an option from a `?` whose arms are a local Vec's vec_get, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (e) an option from a `?` whose arms are a local Vec's vec_get, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ?String o ? == k 1 ( vec_get [String] vs 0 ) ( vec_get [String] vs 0 )
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
