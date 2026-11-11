// string_bound_to_a_value_block_of_its_own_local_handed_to_a_sink: `: String e { : String s ( string_from … ) s }`, then `( eat e )` with `eat` taking a `sink`.
// Closed: a `:` binding's value block whose tail is a binding the block made is that binding to e's drop flag, as `: e s` is: e is a cursor over s, and the sink takes s's value through it (gen_let_or_struct, __let_blk_tail_name; agora #615). Read as a block, e was a borrow with no owner link while s kept a constant drop, so the callee freed the value and the scope's end freed it again.
// main 0b31adec: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #615: a String bound to a value block of the block's own local, handed to a sink
$ `stdlib/core/string.nu`

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String e { : String s ( string_from `inner string long enough for a heap buffer` ) s }
    ( nurl_println_int ( eat e ) )
    ^ 0
}
