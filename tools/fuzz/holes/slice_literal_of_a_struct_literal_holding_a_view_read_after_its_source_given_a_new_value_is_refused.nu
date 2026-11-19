// slice_literal_of_a_struct_literal_holding_a_view_read_after_its_source_given_a_new_value_is_refused: `: [P sl [P | @ P { ( string_from … ) ( string_data src ) } ]`, P a struct of a String and a raw view, then `= src ( string_from … )` and the view read off an element
// Closed (agora #930): a slice literal holds what its elements view, as a struct literal holds what its fields do: it publishes its elements' source expressions (gen_slice_literal), and a binding of it borrows from those sources.
// main 85a31ca: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: `: [P sl [P | @ P { ( string_from … ) ( string_data src ) } ]`, P a struct of a String and a raw view, then `= src ( string_from … )` and the view read off an element
$ `stdlib/core/string.nu`

: P { String o s v }

@ main → i {
    : ~ String src ( string_from `a source string long enough for a heap buffer` )
    : [P sl [P | @ P { ( string_from `o` ) ( string_data src ) }]
    = src ( string_from `another` )
    ~ e sl { ( nurl_println . e v ) }
    ^ 0
}
