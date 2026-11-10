// defer_in_a_block_reads_a_view_of_an_element_cleared_after_the_block: the same through a view of the element taken in the block.
// Closed: as the binding form (agora #491).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #491: the same through a view of the element taken in the block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string dropped by vec_clear before a defer reads it at exit` ) )
    {
        : String e ( vec_at [String] t 0 )
        : s v ( string_data e )
        ; { ( nurl_println v ) }
    }
    ( vec_clear [String] t )
    ^ 0
}
