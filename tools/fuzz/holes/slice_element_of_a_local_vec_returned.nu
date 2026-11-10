// slice_element_of_a_local_vec_returned: `: ( Slice String ) sl (
// slice_from_vec [String] vs )  : String e ( slice_at [String] sl 0 )  ^ e`,
// vs a local: sl owns no drop, so nothing recorded what it views, and e went
// to the caller as its own while vs's drop freed it.
// Closed (agora #553): a slice bound from a call keeps what it may be a lend
// of (`__vljk`), and the chain follows it to vs: e is copied.
// main b997834: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ e` of `( slice_at [String] sl 0 )` bound first, sl a slice of a local Vec: the slice recorded nothing it views, so the element went to the caller as its own and the Vec's drop freed it.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

@ first → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `hello world slice` ) )
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    : String e ( slice_at [String] sl 0 )
    ^ e
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
