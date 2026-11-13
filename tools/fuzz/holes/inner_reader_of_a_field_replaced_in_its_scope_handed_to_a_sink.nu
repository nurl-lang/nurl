// inner_reader_of_a_field_replaced_in_its_scope_handed_to_a_sink: an outer and an inner reader of one field, the field replaced in the inner scope, the inner reader handed to a sink: the outer one owns the old value, and the callee freed it under the outer one (agora #387).
// Closed: a store replacing a field hands its old value to the first reader of that field in bind order (__fs_viewers_take, #354); the borrow walk now makes only that reader its owner, and every later reader a borrow of it (bck_fview_take, agora #387).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #387: the inner reader of a field replaced in its scope handed to a sink while the outer one owns the value
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String outer . o name
    {
        : String inner . o name
        = . o name ( string_from `the new name long enough for the heap` )
        ( gone inner )
    }
    ( nurl_println ( string_data outer ) )
    ^ 0
}
