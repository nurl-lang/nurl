// local_vec_element_bound_then_returned: agora #300 — (a) an element read with vec_at, bound by `:`, then returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (a) an element read with vec_at, bound by `:`, then returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : String e ( vec_at [String] vs 0 )
    ^ e
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
