// defer_in_a_block_reads_a_borrow_of_an_element_cleared_after_the_block: a defer armed in an inner block reads a vec_at binding of that block; the Vec is cleared after the block, before the defer runs at the exit.
// Closed: a binding a defer armed in its block reads lives, with what it borrows, up to the exit where the defer reads it (agora #491).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #491: a defer armed in an inner block reads a vec_at binding of that block; the Vec is cleared after the block, before the defer runs at the exit
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string dropped by vec_clear before a defer reads it at exit` ) )
    {
        : String e ( vec_at [String] t 0 )
        ; { ( nurl_println ( string_data e ) ) }
    }
    ( vec_clear [String] t )
    ^ 0
}
