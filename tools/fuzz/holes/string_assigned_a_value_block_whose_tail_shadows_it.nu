// string_assigned_a_value_block_whose_tail_shadows_it: `= s { : String s ( string_from `inner` ) s }`, then `s` read.
// Closed: gen_assign resolves the target's drop registration before the right-hand side, as it does the target itself: a value block's own locals stay visible to the end of the statement, so one shadowing the name was taken for the target and its value released as the old one (agora #562).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #562: a String assigned a value block whose tail is a block-local shadowing it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    = s { : String s ( string_from `inner` ) s }
    ( nurl_println ( string_data s ) )
    ^ 0
}
