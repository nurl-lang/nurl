// option_owner_given_a_value_block_ending_in_a_call_that_lends_only_it_runs_clean: `= q { ( id q ) }` and `= q { ( println … ) ( id q ) }` over a `?String`: the tail call can hand back only q itself.
// Closed (agora #427): `= q ( id q )` keeps q's value by its key (#342); the block form was read as a block, and q's value was released and stored back freed (heap-use-after-free). It is the call now.
// map: §7.6 | A2 | runs-clean | - | agora #427: an option owner given a value block ending in a call that lends only it
$ `stdlib/core/string.nu`

@ pick String a String b i k → String { ? == k 1 { ^ a } {} ^ b }

@ id ? String x → ?String { ^ x }

@ main → i {
    : ~ ? String q @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    = q { ( id q ) }
    = q { ( nurl_println `x` ) ( id q ) }
    ?? q { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
