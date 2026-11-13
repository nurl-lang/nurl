// option_owner_given_back_by_a_generic_runs_clean: `= o ( pick [?String] o other k )`, a generic callee.
// Guard for agora #427: runs clean on main by the module-end lend answers (#410, #742) and the per-call keys.
// map: §7.6 | A2 | runs-clean | - | agora #427 guard: an option owner given back by a generic
$ `stdlib/core/string.nu`

@ pick [A] A a A b i k → A { ? == k 1 { ^ a } {} ^ b }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick [? String] o other 1 )
    ( show o )
    = o ( pick [? String] o other 0 )
    ( show o )
    ^ 0
}
