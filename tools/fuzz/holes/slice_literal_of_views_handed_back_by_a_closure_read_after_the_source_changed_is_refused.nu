// slice_literal_of_views_handed_back_by_a_closure_read_after_the_source_changed_is_refused: `: [P x ( f sl )` with `f` = `\ [P a → [P { ^ a }` and sl a slice literal of a struct holding a view of src, then `= src ( string_from … )` and the view read off an element of x
// Closed (agora #930): a slice literal holds what its elements view, as a struct literal holds what its fields do: it publishes its elements' source expressions (gen_slice_literal), and a binding of it borrows from those sources.
// main 4d0e1f7: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: `: [P x ( f sl )` with `f` = `\ [P a → [P { ^ a }` and sl a slice literal of a struct holding a view of src, then `= src ( string_from … )` and the view read off an element of x
$ `stdlib/core/string.nu`

: P { String o s v }

@ main → i {
    : ( @ [P [P ) f \ [P a → [P { ^ a }
    : ~ String src ( string_from `a source string long enough for a heap buffer` )
    : P p @ P { ( string_from `o` ) ( string_data src ) }
    : [P sl [P | p ]
    : [P x ( f sl )
    = src ( string_from `another` )
    ~ e x { ( nurl_println . e v ) }
    ^ 0
}
