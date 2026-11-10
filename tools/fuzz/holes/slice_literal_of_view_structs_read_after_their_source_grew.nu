// slice_literal_of_view_structs_read_after_their_source_grew: a slice literal of structs that hold a view, `[V | @ V { ( string_data text ) }]`: the views inside the elements were followed nowhere, and the slice was read after `text` grew.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #545: a slice literal of view-holding structs read after the viewed String grew
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : ~ String text ( string_from `a view in a slice of view structs` )
    : [V ws [V | @ V { ( string_data text ) }]
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println . x v ) }
    ^ 0
}
