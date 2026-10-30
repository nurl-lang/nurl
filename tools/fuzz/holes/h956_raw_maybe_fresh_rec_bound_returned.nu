// H956: agora #206 — the same literal bound first and handed back: its raw string was freed under the caller (raw_maybe_fresh_rec_bound_returned).
// Closed: a raw string a NURL body hands back may be handed over unless no path of the body does (`__ret_unowned`) — __pair_may_own no longer takes the returned-handle summary of one path for the whole function (agora #206).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ maybe_fresh s x i k → s {
    ? != k 0 { ^ ( nurl_str_cat x `!` ) } {}
    ^ x
}

@ build s a → Rec {
    : Rec r @ Rec { ( maybe_fresh a 1 ) 1 }
    ^ r
}

@ main → i {
    : Rec r ( build `abc` )
    ( nurl_println . r name )
    ^ . r n
}
