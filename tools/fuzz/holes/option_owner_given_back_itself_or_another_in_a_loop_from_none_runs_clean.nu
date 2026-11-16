// option_owner_given_back_itself_or_another_in_a_loop_from_none_runs_clean: `= o ( pick o other k )` in a loop, o starting as none, then given a none argument: the key of a none is no buffer
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pick o other k )` in a loop, o starting as none, then given a none argument: the key of a none is no buffer
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { F }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    : ~ i k 0
    ~ < k 6 {
        = o ( pick o other % k 2 )
        ( show o )
        = k + k 1
    }
    : ?String none @ ?String { F }
    = o ( pick o none 0 )
    ( show o )
    = o ( pick o other 0 )
    ( show o )
    ( show other )
    ^ 0
}
