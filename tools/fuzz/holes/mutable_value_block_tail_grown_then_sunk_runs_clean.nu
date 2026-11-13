// mutable_value_block_tail_grown_then_sunk_runs_clean: `: ~ String e { : String s ( string_from … ) s }  ( string_push_str e … )  ( eat e )`: the `: ~` spelling of #615's block tail was left a borrow with no owner link, and the sink freed what s's drop freed again
// Closed: __let_blk_tail_name routes the tail's flag for a `: ~` binding too, now that a reassigned cursor hands over only what it holds (agora #668 item 1).
// main 9052104: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #668: a `: ~` value block's tail binding handed to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : ~ String e { : String s ( string_from `inner string long enough for a heap buffer` ) s }
    ( string_push_str e ` and more` )
    ( nurl_println_int ( eat e ) )
    ^ 0
}
