// slice_of_destructor_view_holders_given_an_element_viewing_a_younger_binding: an element store into a slice of `% Drop` view holders, of a view of a binding declared after the slice: values are dropped newest first, so the element's destructor read the binding freed.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; it ran clean only where the freed buffer was still readable.
// map: §7.6 | A2 | rejected | - | agora #545: an element of an older slice of destructor values given a view of a younger binding
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ [W ws [W | @ W { `lit` }]
    : String younger ( string_from `the younger string, freed before the slice of holders is dropped` )
    : i k 0
    = . ws k @ W { ( string_data younger ) }
    ^ 0
}
