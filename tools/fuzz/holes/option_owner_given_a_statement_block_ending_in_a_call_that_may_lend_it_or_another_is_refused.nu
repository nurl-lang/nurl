// option_owner_given_a_statement_block_ending_in_a_call_that_may_lend_it_or_another_is_refused: `= o { ( nurl_println … ) ( pick o other 1 ) }`: the same with a statement before the tail.
// Closed (agora #427), as option_owner_given_a_value_block_ending_in_a_call_that_may_lend_it_or_another_is_refused.
// map: §7.6 | A2 | rejected | - | agora #427: a value block with a statement before a tail call that may lend the owner or another argument
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o { ( nurl_println `in the block` ) ( pick o other 1 ) }
    ( show o )
    ^ 0
}
