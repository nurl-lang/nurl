// view_stored_into_a_native_slice_element_read_after_its_source_grew: an element store `= . ws k ( string_data text )` put a view into a native slice with nothing recorded: `text` grown, the slice was read.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #545: a view stored into a native slice element, the slice read after the viewed String grew
$ `stdlib/core/string.nu`

@ main → i {
    : ~ [s ws [s | `lit`]
    : ~ String text ( string_from `a string that grows` )
    : i k 0
    = . ws k ( string_data text )
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println x ) }
    ^ 0
}
