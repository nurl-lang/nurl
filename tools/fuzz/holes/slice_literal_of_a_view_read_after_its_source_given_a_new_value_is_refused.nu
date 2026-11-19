// slice_literal_of_a_view_read_after_its_source_given_a_new_value_is_refused: `: s w ( string_data src )  : [s sl [s | w ]`, then `= src ( string_from … )` and an element of sl read
// Closed (agora #930): a slice literal holds what its elements view, as a struct literal holds what its fields do: it publishes its elements' source expressions (gen_slice_literal), and a binding of it borrows from those sources.
// main 4d0e1f7: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: `: s w ( string_data src )  : [s sl [s | w ]`, then `= src ( string_from … )` and an element of sl read
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String src ( string_from `a source string long enough for a heap buffer` )
    : s w ( string_data src )
    : [s sl [s | w ]
    = src ( string_from `another` )
    ~ e sl { ( nurl_println e ) }
    ^ 0
}
