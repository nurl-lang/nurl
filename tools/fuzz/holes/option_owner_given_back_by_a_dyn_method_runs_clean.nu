// option_owner_given_back_by_a_dyn_method_runs_clean: `= o ( pick d o other k )`, `d` a `dyn` trait object.
// Guard for agora #427: runs clean on main by the module-end lend answers (#410, #742) and the per-call keys.
// map: §7.6 | A2 | runs-clean | - | agora #427 guard: an option owner given back by a dyn method
$ `stdlib/core/string.nu`

% Picker [T] {
    @ pick T self ? String a ? String b i k → ?String
}

: P { i z }

% Picker P { @ pick P p ? String a ? String b i k → ?String { ? == k 1 { ^ a } {} ^ b } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : P p @ P { 1 }
    : %Picker d ( dyn Picker p )
    : ~ ? String o @ ?String { T ( string_from `the owned option string, long enough for the heap` ) }
    : ?String other @ ?String { T ( string_from `the other option string, long enough for the heap` ) }
    = o ( pick d o other 1 )
    ( show o )
    = o ( pick d o other 0 )
    ( show o )
    ^ 0
}
