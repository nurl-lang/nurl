// outer_and_inner_readers_of_a_field_then_the_field_replaced: agora #354 — a reader of a field in an outer scope and one in an inner scope, then the field replaced in the inner one: both took the old value, and the inner one's drop freed what the outer one still read.
// Closed: a store replacing a field hands its old value to the first live reader of that field that still holds it and owns nothing yet, in declaration order (the outermost); every later reader is left a view of it (__fs_viewers_take, agora #354).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #354: a reader of a field in an outer scope and one in an inner scope, then the field replaced in the inner one
$ `stdlib/core/string.nu`

: O { String name }

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String outer . o name
    {
        : String inner . o name
        = . o name ( string_from `the new name long enough for the heap` )
        ( nurl_println ( string_data inner ) )
    }
    ( nurl_println ( string_data outer ) )
    ^ 0
}
