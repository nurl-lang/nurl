// slice_get_payload_of_a_local_vec_returned: `?? ( slice_get [String] sl 0 )
// { T e → { ^ e } … }` with sl a slice of a local Vec: the payload went to
// the caller as its own while the Vec's drop freed it.
// Closed (agora #553): the chain follows sl to the Vec it views; e is copied.
// main b997834: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ e` of a `slice_get` payload, the slice of a local Vec: the payload went to the caller as its own and the Vec's drop freed it.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

@ first → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `hello slice_get payload` ) )
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ?? ( slice_get [String] sl 0 ) { T e → { ^ e } F → { ^ ( string_new ) } }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
