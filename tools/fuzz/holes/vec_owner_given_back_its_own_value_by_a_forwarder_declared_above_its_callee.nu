// vec_owner_given_back_its_own_value_by_a_forwarder_declared_above_its_callee: agora #742 — as string_owner_given_back_its_own_value_by_a_forwarder_declared_above_its_callee, with a `( Vec String )` owner
// Closed: a call to a function whose lends still wait on a module-end note — it hands back a callee compiled after it — counts as one that may lend, so the owner keeps a result whose key at run time is its own old value (mem_udrop_keep_same; agora #742).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #742: as string_owner_given_back_its_own_value_by_a_forwarder_declared_above_its_callee, with a `( Vec String )` owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f1 ( Vec String ) p → ( Vec String ) { ^ ( f0 p ) }

@ f0 ( Vec String ) p → ( Vec String ) { ^ p }

@ main → i {
    : ~ ( Vec String ) o ( vec_new [String] )
    ( vec_push [String] o ( string_from `a string long enough to live on the heap for sure` ) )
    = o ( f1 o )
    ( nurl_println ( string_data ( vec_at [String] o 0 ) ) )
    ^ 0
}
