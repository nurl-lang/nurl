// string_owner_given_a_value_block_ending_in_a_call_that_may_lend_it_runs_clean: `= o { ( pick o other k ) }` over a String owner, on the run that hands o back and on the one that hands the other over.
// Closed (agora #427): a handle is told apart by its buffer, as `= o ( pick o other k )` is (#419); the block form was read as a block and o's value was released and stored back (heap-use-after-free). The block's tail call is the call now (`__ud_tt`).
// map: §7.6 | A2 | runs-clean | - | agora #427: a String owner given a value block ending in a call that may lend it
$ `stdlib/core/string.nu`

@ pick String a String b i k → String { ? == k 1 { ^ a } {} ^ b }

@ id ? String x → ?String { ^ x }

@ main → i {
    : ~ String o ( string_from `the owned string, long enough for the heap, yes` )
    : String other ( string_from `the other string, long enough for the heap, yes` )
    = o { ( pick o other 1 ) }
    ( nurl_println ( string_data o ) )
    = o { ( pick o other 0 ) }
    ( nurl_println ( string_data o ) )
    ^ 0
}
