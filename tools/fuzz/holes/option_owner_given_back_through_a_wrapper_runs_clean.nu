// option_owner_given_back_through_a_wrapper_runs_clean: `= o ( id ( pick o other k ) )` over a `?String` owner.
// Guard for agora #427: runs clean on main by the module-end lend answers (#410, #742) and the per-call keys.
// map: §7.6 | A2 | runs-clean | - | agora #427 guard: an option owner given back through a wrapper
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b }

@ id ? String x → ?String { ^ x }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( id ( pick o other 1 ) )
    ( show o )
    = o ( id ( pick o other 0 ) )
    ( show o )
    ^ 0
}
