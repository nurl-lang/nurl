// view_stored_into_a_slice_element_by_a_callee_read_after_its_source_grew: a callee that stores its view parameter into an element of its slice parameter (`= . ws k v`) said nothing of it to its caller: the caller's slice held a view of the caller's String, which then grew.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #545: a callee storing a view parameter into its slice parameter: the caller read the slice after the viewed String grew
$ `stdlib/core/string.nu`

@ put [s ws s v → v {
    : i k 0
    = . ws k v
}

@ main → i {
    : ~ [s ws [s | `lit`]
    : ~ String text ( string_from `a string that grows` )
    ( put ws ( string_data text ) )
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println x ) }
    ^ 0
}
