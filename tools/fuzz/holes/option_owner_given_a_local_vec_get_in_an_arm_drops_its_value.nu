// option_owner_given_a_local_vec_get_in_an_arm_drops_its_value: agora #317 — a `: ~ ?String` that owns its value, given a local Vec's vec_get in one arm: the value it held was never dropped.
// main: accepted; LeakSanitizer reported a leak (h6 also heap-use-after-free before #300).
// map: §7.6 | A2 | runs-clean | - | agora #317: a `: ~ ?String` that owns its value, given a local Vec's vec_get in one arm: the value it held was never dropped (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ make → ?String {
    ^ @ ?String { T ( string_from `a fresh string long enough for the heap` ) }
}

@ pick i k → i {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( make )
    ? == k 2 { = o ( vec_get [String] vs 0 ) } {}
    ^ 0
}

@ main → i {
    ( pick 1 )
    ( pick 2 )
    ^ 0
}
