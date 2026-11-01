// binding_repointed_in_arms_at_local_and_param_elements_returned: agora #300 — (h3) a `: ~` binding re-pointed in the arms at an element of a local Vec or of a parameter Vec, returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (h3) a `: ~` binding re-pointed in the arms at an element of a local Vec or of a parameter Vec, returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick ( Vec String ) ps i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ String e ( string_from `fresh` )
    ? == k 1 { = e ( vec_at [String] vs 0 ) } { = e ( vec_at [String] ps 0 ) }
    ^ e
}

@ main → i {
    : ( Vec String ) ps ( vec_new [String] )
    ( vec_push [String] ps ( string_from `a parameter element long enough for the heap` ) )
    : String a ( pick ps 1 )
    : String b ( pick ps 2 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
