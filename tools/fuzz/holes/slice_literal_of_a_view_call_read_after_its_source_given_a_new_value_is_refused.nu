// slice_literal_of_a_view_call_read_after_its_source_given_a_new_value_is_refused: `: [s sl [s | ( string_data src ) ]`, then `= src ( string_from … )` and an element of sl read
// Closed (agora #930): a slice literal holds what its elements view, as a struct literal holds what its fields do: it publishes its elements' source expressions (gen_slice_literal), and a binding of it borrows from those sources.
// main 85a31ca: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: `: [s sl [s | ( string_data src ) ]`, then `= src ( string_from … )` and an element of sl read
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String src ( string_from `a source string long enough for a heap buffer` )
    : [s sl [s | ( string_data src )]
    = src ( string_from `another` )
    ~ e sl { ( nurl_println e ) }
    ^ 0
}
