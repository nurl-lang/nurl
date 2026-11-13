// second_reader_of_a_replaced_field_read_after_the_first_is_reassigned: two readers of one String field, the field replaced, the first reader given a new value, then the second read: the old value the first one owned was released under it (agora #387).
// Closed: a store replacing a field hands its old value to the first reader of that field in bind order (__fs_viewers_take, #354); the borrow walk now makes only that reader its owner, and every later reader a borrow of it (bck_fview_take, agora #387).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #387: the second reader of a replaced field read after the first is given a new value
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : ~ String g1 . o name
    : String g2 . o name
    = . o name ( string_from `the new name long enough for the heap` )
    = g1 ( string_from `another value long enough for the heap` )
    ( nurl_println ( string_data g2 ) )
    ^ 0
}
