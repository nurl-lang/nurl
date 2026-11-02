// two_inner_readers_of_a_field_then_the_field_replaced: agora #354 — two readers of a field in one inner scope, then the field replaced there: both dropped the old value at the scope's end.
// Closed: a store replacing a field hands its old value to the first live reader of that field that still holds it and owns nothing yet, in declaration order (the outermost); every later reader is left a view of it (__fs_viewers_take, agora #354).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #354: two readers of a field in one inner scope, then the field replaced there
$ `stdlib/core/string.nu`

: O { String name }

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    {
        : String inner . o name
        : String inner2 . o name
        = . o name ( string_from `the new name long enough for the heap` )
        ( nurl_println ( string_data inner2 ) )
    }
    ( nurl_println ( string_data . o name ) )
    ^ 0
}
