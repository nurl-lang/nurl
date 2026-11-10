// defer_in_a_block_reads_a_borrow_of_an_unchanged_element_runs_clean: a defer armed in an inner block reads a vec_at binding of that block; the Vec is not changed after it.
// Control for agora #491: keeping the borrow to the exit refuses no program that leaves its container alone.
// map: §2.10 | A2 | runs-clean | - | agora #491: a defer armed in an inner block reads a vec_at binding of that block; the Vec is not changed after it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the vec holds, long enough for the heap` ) )
    {
        : String e ( vec_at [String] t 0 )
        ; { ( nurl_println ( string_data e ) ) }
    }
    ( nurl_println `the vec is not changed after the block` )
    ^ 0
}
