// option_repointed_in_arms_at_local_and_param_vec_gets_payload_returned: agora #300 — (h4) a `: ~` option re-pointed in the arms at a local Vec's vec_get or a parameter's, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (h4) a `: ~` option re-pointed in the arms at a local Vec's vec_get or a parameter's, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick ( Vec String ) ps i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    ? == k 2 { = o ( vec_get [String] ps 0 ) } {}
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : ( Vec String ) ps ( vec_new [String] )
    ( vec_push [String] ps ( string_from `a parameter element long enough for the heap` ) )
    : String a ( pick ps 1 )
    : String b ( pick ps 2 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ( nurl_println ( string_data ( vec_at [String] ps 0 ) ) )
    ^ 0
}
