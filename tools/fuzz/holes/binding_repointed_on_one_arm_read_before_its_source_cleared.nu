// binding_repointed_on_one_arm_read_before_its_source_cleared: agora #311 — the twin of binding_repointed_on_one_arm_read_after_its_source_cleared, reading the binding before the Vec is cleared (the shape the fix must keep).
// Closed: at a `?` / `??` join a binding borrows from what it borrowed on either path: each arm is walked from the facts the join started from, and the borrow facts an arm changes (its sources `bs_`, the buffers it views `vi_`, the field it views `fb_`/`fp_`) are joined, as A2's `ite` joins the arms' dependencies (bck_put_bf, __cj_note, __cj_join2; agora #311).
// main: accepted; ran clean.
// map: §2.10 | A1 | runs-clean | - | agora #311: a binding re-pointed on one `?` arm, read before the clear
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ String e ( vec_at [String] vs 0 )
    ? == k 1 { = e ( string_from `a fresh string long enough for the heap` ) } {}
    ( nurl_println ( string_data e ) )
    ( vec_clear [String] vs )
    ^ ( string_from `done` )
}

@ main → i {
    : String r ( pick 0 )
    ( nurl_println ( string_data r ) )
    : String r1 ( pick 1 )
    ( nurl_println ( string_data r1 ) )
    ^ 0
}
