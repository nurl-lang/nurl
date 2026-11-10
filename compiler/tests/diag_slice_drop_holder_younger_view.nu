// diag_slice_drop_holder_younger_view.nu — a slice whose elements run a
// destructor that may read a view is dropped after every binding declared
// after it: an element given a view of such a binding would read it freed
// (Agora #545; the slice sibling of diag_drop_holder_younger_view.nu).

$ `stdlib/core/string.nu`

: Shout { s text }

% Drop Shout { @ drop Shout self → v { ( nurl_println . self text ) } }

@ main → i {
    : ~ [Shout ws [Shout | @ Shout { `lit` }]
    : String younger ( string_from `the younger string, freed before the slice of holders is dropped` )
    : i k 0
    = . ws k @ Shout { ( string_data younger ) }
    ^ 0
}
