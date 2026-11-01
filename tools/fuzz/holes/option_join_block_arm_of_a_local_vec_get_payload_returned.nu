// option_join_block_arm_of_a_local_vec_get_payload_returned: agora #300 — (j7) a `??` over an option bound from a local Vec's vec_get, its payload the tail of an arm block, the join returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (j7) a `??` over an option bound from a local Vec's vec_get, its payload the tail of an arm block, the join returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ?String o ( vec_get [String] vs 0 )
    ^ ?? o { T e → { ( nurl_println `arm` ) e } F → ( string_from `none` ) }
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
