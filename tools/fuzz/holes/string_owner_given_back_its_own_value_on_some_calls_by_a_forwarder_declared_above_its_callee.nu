// string_owner_given_back_its_own_value_on_some_calls_by_a_forwarder_declared_above_its_callee: agora #742 — `@ f0 String p b c → String { ^ ? c p ( mk ) }` below its forwarder f1, `= o ( f1 o c )` run with c true and false: lent on one run, fresh on the other
// Closed: a call to a function whose lends still wait on a module-end note — it hands back a callee compiled after it — counts as one that may lend, so the owner keeps a result whose key at run time is its own old value (mem_udrop_keep_same; agora #742).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #742: `@ f0 String p b c → String { ^ ? c p ( mk ) }` below its forwarder f1, `= o ( f1 o c )` run with c true and false: lent on one run, fresh on the other
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to live on the heap for sure` ) }

@ f1 String p b c → String { ^ ( f0 p c ) }

@ f0 String p b c → String { ^ ? c p ( mk ) }

@ run b c → v {
    : ~ String o ( mk )
    = o ( f1 o c )
    ( nurl_println ( string_data o ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
