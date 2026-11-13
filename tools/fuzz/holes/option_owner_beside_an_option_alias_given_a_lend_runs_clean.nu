// option_owner_beside_an_option_alias_given_a_lend_runs_clean: `: ?String p ( id o )` beside `: ~ ?String o`, then `= o ( vec_at rs 0 )` and `= o @ ?String { T … }`.
// Guard for agora #366: an option-typed alias of an option owner compiles (it once made clang reject the IR) and runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #366 guard: an option owner beside an option alias, given a lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ? String x → ?String { ^ x }

@ main → i {
    : ( Vec ? String ) rs ( vec_new [? String] )
    ( vec_push [? String] rs @ ?String { T ( string_from `an element string, long enough for the heap allocation` ) } )
    : ~ ? String o @ ?String { T ( string_from `the owner string, long enough for the heap allocation` ) }
    : ?String p ( id o )
    = o ( vec_at [? String] rs 0 )
    = o @ ?String { T ( string_from `a fresh owner string, long enough for the heap allocation` ) }
    ^ 0
}
