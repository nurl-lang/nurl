// option_owner_given_a_value_block_ending_in_a_call_that_may_lend_it_or_another_is_refused: `= o { ( pick o other k ) }` and `= o { ( println … ) ( pick o other k ) }` over a `?String` owner.
// Closed (agora #427): the direct form `= o ( pick o other k )` is refused (#412): no per-run answer is right on both kinds of run. Spelled inside a value block it was let through, and the run that handed o's own value back freed it under o (heap-use-after-free). A value block whose tail is a call is that call's value to gen_assign's ownership rules now (`__ud_tt`), and the same refusal names the fix.
// map: §7.6 | A2 | rejected | - | agora #427: a value block ending in a call that may lend the owner or another argument
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o { ( pick o other 1 ) }
    ( show o )
    = o { ( pick o other 0 ) }
    ( show o )
    ^ 0
}
