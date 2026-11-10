// slice_field_element_of_an_older_struct_given_a_view_of_a_younger_binding: an element store through a field, `= . . h items k @ W { view }`, of a view of a binding declared after `h`, whose slice field holds `% Drop` view holders: `h` is dropped after the binding.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; it ran clean only where the freed buffer was still readable.
// map: §7.6 | A2 | rejected | - | agora #545: an element of a slice field of an older struct given a destructor value viewing a younger binding
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: H { [W items i n }

@ main → i {
    : ~ H h @ H { [W | @ W { `lit` }] 1 }
    : String younger ( string_from `the younger string, freed before the holder is dropped` )
    : i k 0
    = . . h items k @ W { ( string_data younger ) }
    ^ 0
}
