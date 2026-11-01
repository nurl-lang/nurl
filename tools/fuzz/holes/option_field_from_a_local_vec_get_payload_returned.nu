// option_field_from_a_local_vec_get_payload_returned: agora #300 — (f) an option stored in a struct field from a local Vec's vec_get, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (f) an option stored in a struct field from a local Vec's vec_get, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: H { ? String o }

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : H h @ H { ( vec_get [String] vs 0 ) }
    ?? . h o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
