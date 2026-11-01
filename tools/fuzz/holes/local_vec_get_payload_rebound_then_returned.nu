// local_vec_get_payload_rebound_then_returned: agora #300 — (g) a payload of a local Vec's vec_get re-bound by `:`, then returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (g) a payload of a local Vec's vec_get re-bound by `:`, then returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    ?? ( vec_get [String] vs 0 ) { T e → { : String e2 e ^ e2 } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
