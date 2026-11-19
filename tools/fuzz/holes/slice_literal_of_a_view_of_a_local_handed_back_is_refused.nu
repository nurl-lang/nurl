// slice_literal_of_a_view_of_a_local_handed_back_is_refused: `@ loc → [s { : String t ( string_from … )  ^ [s | ( string_data t ) ] }`, its result read by the caller after t was released
// Closed (agora #930): a slice literal holds what its elements view, so one handed back holding a view of a local is a view of that local, refused as `^ ( string_data t )` is.
// main 85a31ca: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #930: a slice literal holding a view of a function's local String, handed back and read by the caller
$ `stdlib/core/string.nu`

@ loc → [s {
    : String t ( string_from `a local string long enough for a heap buffer` )
    ^ [s | ( string_data t )]
}

@ main → i {
    : [s sl ( loc )
    ~ e sl { ( nurl_println e ) }
    ^ 0
}
