// option_owner_given_another_argument_then_that_one_replaced: `= o ( pick o other 0 )` then other given a new value: o borrows the other on that run, so it is a use of a replaced value
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | rejected | - | agora #412: `= o ( pick o other 0 )` then other given a new value: o borrows the other on that run, so it is a use of a replaced value
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ~ ? String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick o other 0 )
    = other @ ?String { T ( string_from `a third option string, long enough for the heap, too` ) }
    ( show o )
    ^ 0
}
