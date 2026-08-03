// defer_drop_reclaim.nu — a `;` defer must not suppress auto-drop.
// Root cause (found while building the structural fuzzer, 2026-08-03):
// every mem_drop_* helper emitted NOTHING when the defer chain was
// non-empty, and fn_cleanup emitted only the ret — so one `;` anywhere
// in a function disabled every owned-value drop in it (strings, struct
// fields, %Drop values, closure envs, slices), at scope exits AND at
// function exit. Loop-body %Drop values leaked unboundedly.
// Now: values registered BEFORE a defer (its body may reference them)
// are reclaimed in fn_cleanup after the chain runs; everything
// registered after drops normally at scope exit / return.
// Run with LSAN_DETECT_LEAKS=1: must be leak-clean.

$ `stdlib/core/string.nu`

: ~ i g_drops 0

: DH { * u buf }

% Drop ( DH ) { @ drop DH h → v { = g_drops + g_drops 1 ( nurl_free # s . h buf ) } }

@ loop_drops_with_defer → i {
    ; { ( nurl_print `defer A saw ` ) ( nurl_print ( nurl_str_int g_drops ) ) ( nurl_print ` drops\n` ) }
    : ~ i k 0
    ~ < k 5 {
        : DH h @ DH { # *u ( malloc 16 ) }
        = k + k 1
    }
    ^ g_drops
}

@ pre_defer_string_use → v {
    : s msg ( nurl_str_cat `pre` `-defer string` )
    // The defer body reads a string registered BEFORE it — the string
    // must still be alive when the chain runs at function exit
    // (reclaimed only in fn_cleanup, after the chain).
    ; { ( nurl_print msg ) ( nurl_print `\n` ) }
    : s post ( nurl_str_cat `post-` `defer string` )
    ( nurl_print post ) ( nurl_print `\n` )
}

@ arm_drop_with_defer → i {
    ; { ( nurl_print `defer B\n` ) }
    ? > 2 1 {
        : DH h @ DH { # *u ( malloc 16 ) }
        : s t ( nurl_str_cat `arm` `-local` )
        ( nurl_print t ) ( nurl_print `\n` )
    } {}
    ^ g_drops
}

@ main → i {
    : i a ( loop_drops_with_defer )
    ( nurl_print `loop drops: ` ) ( nurl_print ( nurl_str_int a ) ) ( nurl_print `\n` )
    ( pre_defer_string_use )
    : i b ( arm_drop_with_defer )
    ( nurl_print `arm drops total: ` ) ( nurl_print ( nurl_str_int b ) ) ( nurl_print `\n` )
    ^ 0
}
