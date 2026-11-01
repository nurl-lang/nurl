// value_block_tail_binding_of_a_local_vec_element_bound_then_returned: agora #300 — (j6) a value block whose tail is a binding of a local Vec's element, bound by `:` and returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (j6) a value block whose tail is a binding of a local Vec's element, bound by `:` and returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : String r { : String e3 ( vec_at [String] vs 0 ) e3 }
    ^ r
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
