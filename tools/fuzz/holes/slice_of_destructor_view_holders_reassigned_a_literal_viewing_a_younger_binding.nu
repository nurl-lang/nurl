// slice_of_destructor_view_holders_reassigned_a_literal_viewing_a_younger_binding: a slice of `% Drop` view holders reassigned a literal that views a binding declared after it: dropped newest first, the element's destructor read the binding freed.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; it ran clean only where the freed buffer was still readable.
// map: §7.6 | A2 | rejected | - | agora #545: an older slice of destructor values reassigned a literal viewing a younger binding
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ [W ws [W | @ W { `lit` }]
    : String younger ( string_from `the younger string, freed before the slice of holders is dropped` )
    = ws [W | @ W { ( string_data younger ) }]
    ^ 0
}
