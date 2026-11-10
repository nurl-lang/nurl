// slice_literal_of_views_read_after_their_source_grew: a native slice literal `[s | ( string_data text )]` holds a view of `text`, and what a slice's elements view was followed nowhere: `text` grown (its buffer moved), the slice was still read.
// Closed: a slice literal, an element store and a returned slice are followed for the views they hold, as a struct literal, a field store and a returned struct are (agora #545): the slice depends on what its elements view.
// main (before this PR): accepted; AddressSanitizer heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #545: a slice literal holding a view of a String read after the String grew
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String text ( string_from `a view in a slice of raw strings` )
    : [s ws [s | ( string_data text )]
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println x ) }
    ^ 0
}
