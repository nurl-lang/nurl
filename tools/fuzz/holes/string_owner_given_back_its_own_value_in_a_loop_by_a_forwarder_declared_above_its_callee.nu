// string_owner_given_back_its_own_value_in_a_loop_by_a_forwarder_declared_above_its_callee: agora #742 — as string_owner_given_back_its_own_value_by_a_forwarder_declared_above_its_callee, `= o ( f1 o )` three times in a `~` loop
// Closed: a call to a function whose lends still wait on a module-end note — it hands back a callee compiled after it — counts as one that may lend, so the owner keeps a result whose key at run time is its own old value (mem_udrop_keep_same; agora #742).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #742: as string_owner_given_back_its_own_value_by_a_forwarder_declared_above_its_callee, `= o ( f1 o )` three times in a `~` loop
$ `stdlib/core/string.nu`

@ f1 String p → String { ^ ( f0 p ) }

@ f0 String p → String { ^ p }

@ main → i {
    : ~ String o ( string_from `a string long enough to live on the heap for sure` )
    : ~ i k 0
    ~ < k 3 {
        = o ( f1 o )
        = k + k 1
    }
    ( nurl_println ( string_data o ) )
    ^ 0
}
