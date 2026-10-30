// H928: agora #201 — a closure body's early `^` after a `?` arm parked a raw string's slot: the drain at a closure's `^` was skipped (raw_slot_closure_early_return).
// Closed: gen_ret_term drains the deferred slots in a closure body too — the list is the body's own there (agora #201).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`

@ part i k → b { ^ == 0 % k 2 }

@ main → i {
    : ( @ i i ) f \ i n → i {
        : ~ s acc ( nurl_str_cat `a` `` )
        ? ! ( part n ) {
            : s o ( nurl_str_cat `b` `` )
            = acc o
        } {}
        ? == n 3 { ^ 7 } {}
        ^ ( nurl_str_len acc )
    }
    ( nurl_println_int ( f 3 ) )
    ( nurl_println_int ( f 4 ) )
    ^ 0
}
