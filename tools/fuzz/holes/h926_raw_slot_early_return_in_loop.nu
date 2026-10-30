// H926: agora #201 — `~ < k n { ? == k 3 { ^ … } {}  ? ! ( part k ) { : s o … = acc o } {} … }`: o's slot, kept past its block, freed by the fall-off only — the early `^` of a later pass leaked it (raw_slot_early_return_in_loop).
// Closed: At a loop body's back-edge, a raw-string slot parked there after one of the function's exits is freed and emptied (mem_drain_deferred_since, agora #201).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

@ part i k → b { ^ == 0 % k 2 }

@ f i n → s {
    : ~ s acc ( nurl_str_cat `a` `` )
    : ~ i k 0
    ~ < k n {
        ? == k 3 { ^ ( nurl_str_cat `` `` ) } {}
        ? ! ( part k ) {
            : s o ( nurl_str_cat `b` `` )
            = acc o
        } {}
        = k + k 1
    }
    : s r ( nurl_str_cat acc `` )
    ^ r
}

@ main → i {
    : s r ( f 5 )
    ( nurl_println r )
    : s q ( f 2 )
    ( nurl_println q )
    ^ 0
}
