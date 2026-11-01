// binding_repointed_on_one_arm_read_after_its_source_cleared: agora #311 — a binding borrowing a Vec's element, given a fresh String on one arm of a `?` only, read after the Vec is cleared: on the other path it still borrows the element.
// Closed: at a `?` / `??` join a binding borrows from what it borrowed on either path: each arm is walked from the facts the join started from, and the borrow facts an arm changes (its sources `bs_`, the buffers it views `vi_`, the field it views `fb_`/`fp_`) are joined, as A2's `ite` joins the arms' dependencies (bck_put_bf, __cj_note, __cj_join2; agora #311).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #311: a binding re-pointed on one `?` arm, its other path's source cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ String e ( vec_at [String] vs 0 )
    ? == k 1 { = e ( string_from `a fresh string long enough for the heap` ) } {}
    ( vec_clear [String] vs )
    ( nurl_println ( string_data e ) )
    ^ ( string_from `done` )
}

@ main → i {
    : String r ( pick 0 )
    ( nurl_println ( string_data r ) )
    ^ 0
}
