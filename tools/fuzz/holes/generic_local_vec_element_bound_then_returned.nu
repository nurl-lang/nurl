// generic_local_vec_element_bound_then_returned: agora #300 — (g1) a generic function returns an element of its local Vec bound by `:` (T = String).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (g1) a generic function returns an element of its local Vec bound by `:` (T = String) (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick_of [T] T x → T {
    : ( Vec T ) vs ( vec_new [T] )
    ( vec_push [T] vs x )
    : T e ( vec_at [T] vs 0 )
    ^ e
}

@ main → i {
    : String s ( pick_of [String] ( string_from `an element string long enough for the heap` ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
