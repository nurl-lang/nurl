// option_owner_given_back_itself_or_another_by_a_callee_above_runs_clean: `= o ( pickb o other k )`, pickb compiled before the call: o keeps its value where the run hands it back and borrows the other where it does not, by the payload key
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pickb o other k )`, pickb compiled before the call: o keeps its value where the run hands it back and borrows the other where it does not, by the payload key
$ `stdlib/core/string.nu`
@ pickb ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }
@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }
@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pickb o other 1 )
    ( show o )
    = o ( pickb o other 0 )
    ( show o )
    ^ 0
}
