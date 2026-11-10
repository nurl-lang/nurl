// slice_field_of_destructor_view_holders_dropped_after_their_source_grew: a struct whose field is a slice of `% Drop` values that hold a view: the struct's drop runs their destructors over a view of `text`, grown and moved since.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free in the destructor.
// map: §7.6 | A2 | rejected | - | agora #545: a struct with a slice field of destructor values viewing a String dropped after the String grew
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: H { [W ws i n }

@ main → i {
    : ~ String text ( string_from `a view holder with a destructor in a slice field` )
    : H h @ H { [W | @ W { ( string_data text ) }] 1 }
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ^ 0
}
