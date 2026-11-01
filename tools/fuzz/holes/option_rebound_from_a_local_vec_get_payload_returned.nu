// option_rebound_from_a_local_vec_get_payload_returned: agora #300 — (c) an option bound from a local Vec's vec_get, re-bound by name, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (c) an option bound from a local Vec's vec_get, re-bound by name, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ?String o ( vec_get [String] vs 0 )
    : ?String o2 o
    ?? o2 { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
