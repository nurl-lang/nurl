// field_reader_repointed_at_an_element_then_the_field_replaced_and_sunk: a reader of `. o name` given a `vec_at` element with `=`, the field replaced, the reader handed to a sink — accepted, a heap-use-after-free: the walk still took the reader for the field's viewer, so the replace made it the old value's owner, and the sink freed the Vec's element (found fixing agora #387).
// Closed: an `=` that gives a binding a new value clears its field-viewer facts (`fb_` / `fp_`), as a `let` does; its new value's own borrow row says whether it views a field.
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | found fixing agora #387: a field reader re-pointed at a vec_at element, the field replaced, the reader sunk (UAF)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element long enough for the heap` ) )
    : ~ String g1 . o name
    = g1 ( vec_at [String] vs 0 )
    = . o name ( string_from `the new name long enough for the heap` )
    ( gone g1 )
    ( nurl_println ( string_data ( vec_at [String] vs 0 ) ) )
    ^ 0
}
