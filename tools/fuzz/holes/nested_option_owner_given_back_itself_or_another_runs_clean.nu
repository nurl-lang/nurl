// nested_option_owner_given_back_itself_or_another_runs_clean: `= o ( pick o other k )` with o a `? ?String`: keyed by its innermost payload
// main 3358873a: refused by gen_assign's #412 rule when the callee is compiled before the call (and accepted below it); the key test answers each run (AGORA-869).
// map: §7.6 | A2 | runs-clean | - | agora #412: `= o ( pick o other k )` with o a `? ?String`: keyed by its innermost payload
$ `stdlib/core/string.nu`

@ pick ? ? String a ? ? String b i k → ? ?String { ? == k 1 { ^ a } {} ^ b }

@ main → i {
    : ~ ? ? String o @ ? ?String { T @ ?String { T ( string_from `the owned option string, long enough for the heap` ) } }
    : ? ?String other @ ? ?String { T @ ?String { T ( string_from `the other option string, long enough for the heap` ) } }
    = o ( pick o other 0 )
    = o ( pick o other 1 )
    = o ( pick o other 0 )
    ?? o { T i → { ?? i { T s → { ( nurl_println ( string_data s ) ) } F → {} } } F → {} }
    ^ 0
}
