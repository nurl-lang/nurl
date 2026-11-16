// option_owner_given_another_argument_then_moved_runs_clean: `= o ( pick o other 0 )` then o bound to a new name: the new name owns what o owned on each run
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pick o other 0 )` then o bound to a new name: the new name owns what o owned on each run
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ keep ? String o → ?String { ^ o }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick o other 0 )
    : ?String moved o
    ( show moved )
    ( show other )
    ^ 0
}
