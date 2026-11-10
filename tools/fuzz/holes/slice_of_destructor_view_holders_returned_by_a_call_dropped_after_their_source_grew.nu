// slice_of_destructor_view_holders_returned_by_a_call_dropped_after_their_source_grew: a function returning a slice literal built over its view parameter (`^ [W | @ W { v }]`) handed back views its summary did not mention: the caller's slice was dropped, destructors and all, after the viewed String grew.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free in the destructor.
// map: §2.8 | A2 | rejected | - | agora #545: a returned slice literal holding views of a parameter: the result dropped after the viewed String grew
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ mk s v → [W { ^ [W | @ W { v }] }

@ main → i {
    : ~ String text ( string_from `a view holder with a destructor in a returned slice` )
    : [W ws ( mk ( string_data text ) )
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ^ 0
}
