// raw_maybe_fresh_rec_returned: agora #206 — `^ @ Rec { ( maybe_fresh a 1 ) 1 }`, maybe_fresh = `? != k 0 { ^ ( nurl_str_cat x ! ) } {}  ^ x`: the fresh raw string, stored as a view, leaked (raw_maybe_fresh_rec_returned).
// Closed: a raw string a NURL body hands back may be handed over unless no path of the body does (`__ret_unowned`) — __pair_may_own no longer takes the returned-handle summary of one path for the whole function (agora #206).
// main: accepted; LeakSanitizer reported a leak.
// map: §2.13 | A2 | rejected | h955 | a raw string a call may hand over fresh, stored in a returned struct: taken for a lend (one path's `^ x`), it leaked
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ maybe_fresh s x i k → s {
    ? != k 0 { ^ ( nurl_str_cat x `!` ) } {}
    ^ x
}

@ build s a → Rec {
    ^ @ Rec { ( maybe_fresh a 1 ) 1 }
}

@ main → i {
    : Rec r ( build `abc` )
    ( nurl_println . r name )
    ^ . r n
}
