// option_repointed_on_both_arms_swapped_read_after_one_source_cleared: agora #311 — as option_repointed_on_both_arms_read_after_one_source_cleared, the arms swapped (refused before).
// Closed: at a `?` / `??` join a binding borrows from what it borrowed on either path: each arm is walked from the facts the join started from, and the borrow facts an arm changes (its sources `bs_`, the buffers it views `vi_`, the field it views `fb_`/`fp_`) are joined, as A2's `ite` joins the arms' dependencies (bck_put_bf, __cj_note, __cj_join2; agora #311).
// main: rejected.
// map: §2.10 | A1 | rejected | - | agora #311: both `?` arms re-point an option binding, swapped
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ( Vec String ) ps ( vec_new [String] )
    ( vec_push [String] ps ( string_from `another element string long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] ( vec_new [String] ) 0 )
    ? == k 1 { = o ( vec_get [String] ps 0 ) } { = o ( vec_get [String] vs 0 ) }
    ( vec_clear [String] vs )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } }
    ^ ( string_from `done` )
}

@ main → i {
    : String r ( pick 0 )
    ( nurl_println ( string_data r ) )
    ^ 0
}
