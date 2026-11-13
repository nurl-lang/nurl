// second_reader_of_a_replaced_field_handed_to_a_sink: two readers of one String field, the field replaced, then the SECOND reader handed to a parameter that takes it: it was left a view of the old value the first reader owns, and the callee freed it under the first (agora #387).
// Closed: a store replacing a field hands its old value to the first reader of that field in bind order (__fs_viewers_take, #354); the borrow walk now makes only that reader its owner, and every later reader a borrow of it (bck_fview_take, agora #387).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #387: the second reader of a replaced field handed to a sink
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String g1 . o name
    : String g2 . o name
    = . o name ( string_from `the new name long enough for the heap` )
    ( gone g2 )
    ( nurl_println ( string_data g1 ) )
    ^ 0
}
