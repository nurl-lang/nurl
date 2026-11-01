// binding_repointed_on_both_arms_read_after_one_source_cleared: agora #311 — a binding given a different Vec's element on each arm of a `?`, read after the then-arm's Vec is cleared: the walk kept only the else-arm's source.
// Closed: at a `?` / `??` join a binding borrows from what it borrowed on either path: each arm is walked from the facts the join started from, and the borrow facts an arm changes (its sources `bs_`, the buffers it views `vi_`, the field it views `fb_`/`fp_`) are joined, as A2's `ite` joins the arms' dependencies (bck_put_bf, __cj_note, __cj_join2; agora #311).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #311: both `?` arms re-point a binding; the then-arm's source cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ( Vec String ) ps ( vec_new [String] )
    ( vec_push [String] ps ( string_from `another element string long enough for the heap` ) )
    : ~ String e ( string_from `a fresh string long enough for the heap` )
    ? == k 1 { = e ( vec_at [String] vs 0 ) } { = e ( vec_at [String] ps 0 ) }
    ( vec_clear [String] vs )
    ( nurl_println ( string_data e ) )
    ^ ( string_from `done` )
}

@ main → i {
    : String r ( pick 1 )
    ( nurl_println ( string_data r ) )
    ^ 0
}
