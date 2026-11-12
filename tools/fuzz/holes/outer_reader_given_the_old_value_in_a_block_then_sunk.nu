// outer_reader_given_the_old_value_in_a_block_then_sunk: an outer and an inner reader of one field, the field replaced inside the block (the outer reader takes the old value), the outer one handed to a sink after the block — the struct's NEW value was taken out of the field with it and leaked (found fixing agora #387).
// Closed: whether a store replacing the field handed a reader the old value (`__ftk`) is kept in the reader's own scope (__fview_note), not the block the store ran in, so after the block the hand-over still leaves the field's new value in place (__field_holds_cond).
// main (before this PR): LeakSanitizer reported the new String (88 bytes in 2 blocks).
// map: §7.6 | A2 | runs-clean | - | found fixing agora #387: an outer reader that took a field's old value in an inner block, sunk after it — the field's new value leaked
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String outer . o name
    {
        : String inner . o name
        = . o name ( string_from `the new name long enough for the heap` )
        ( nurl_println ( string_data inner ) )
    }
    ( gone outer )
    ^ 0
}
