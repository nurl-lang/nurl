// raw_slot_early_return_in_foreach: agora #201 — the same in a `~ k xs` loop (raw_slot_early_return_in_foreach).
// Closed: At a loop body's back-edge, a raw-string slot parked there after one of the function's exits is freed and emptied (mem_drain_deferred_since, agora #201).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h927 | agora #201: the same in a `~ k xs` loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ part i k → b { ^ == 0 % k 2 }

@ f ( Vec i ) xs → s {
    : ~ s acc ( nurl_str_cat `a` `` )
    ~ k xs {
        ? == k 3 { ^ ( nurl_str_cat `` `` ) } {}
        ? ! ( part k ) {
            : s o ( nurl_str_cat `b` `` )
            = acc o
        } {}
    }
    : s r ( nurl_str_cat acc `` )
    ^ r
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 ) ( vec_push [i] xs 2 ) ( vec_push [i] xs 3 ) ( vec_push [i] xs 4 )
    : s r ( f xs )
    ( nurl_println r )
    ^ 0
}
