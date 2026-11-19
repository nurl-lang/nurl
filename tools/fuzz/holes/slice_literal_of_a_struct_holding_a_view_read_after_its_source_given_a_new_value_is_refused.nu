// slice_literal_of_a_struct_holding_a_view_read_after_its_source_given_a_new_value_is_refused: `: Q p @ Q { ( string_data src ) 1 }  : [Q sl [Q | p ]`, Q a struct with a raw view field, then `= src ( string_from … )` and the field read off an element
// Closed (agora #930): a slice literal holds what its elements view, as a struct literal holds what its fields do: it publishes its elements' source expressions (gen_slice_literal), and a binding of it borrows from those sources.
// main 85a31ca: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: `: Q p @ Q { ( string_data src ) 1 }  : [Q sl [Q | p ]`, Q a struct with a raw view field, then `= src ( string_from … )` and the field read off an element
$ `stdlib/core/string.nu`

: Q { s v i n }

@ main → i {
    : ~ String src ( string_from `a source string long enough for a heap buffer` )
    : Q p @ Q { ( string_data src ) 1 }
    : [Q sl [Q | p]
    = src ( string_from `another` )
    ~ e sl { ( nurl_println . e v ) }
    ^ 0
}
