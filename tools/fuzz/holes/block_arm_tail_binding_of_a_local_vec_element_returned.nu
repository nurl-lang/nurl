// block_arm_tail_binding_of_a_local_vec_element_returned: agora #300 — (j5) a `?` arm block whose tail is a binding of a local Vec's element, the join returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (j5) a `?` arm block whose tail is a binding of a local Vec's element, the join returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    ^ ? == k 1 { : String e3 ( vec_at [String] vs 0 ) e3 } ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    : String t ( pick 2 )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data t ) )
    ^ 0
}
