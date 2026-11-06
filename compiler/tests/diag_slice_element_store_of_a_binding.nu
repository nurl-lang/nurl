// diag_slice_element_store_of_a_binding.nu — a slice of Strings owns its
// elements (Agora #485), so a binding stored into one of them would be a
// second owner of its value: the slice drops it, and the binding was read
// on after. The store is refused; a copy or a value made for the slice is
// stored instead.
$ `stdlib/core/string.nu`

@ main → i {
    : String b ( string_from `a binding stored into a slice element` )
    : [String sl [String | ( string_from `the element the store would replace` )]
    = . sl 0 b
    ( nurl_println ( string_data b ) )
    ^ 0
}
