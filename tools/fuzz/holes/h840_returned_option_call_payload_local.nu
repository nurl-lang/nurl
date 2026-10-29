// H840: agora #189 — `^ @ ?String { T ( gets w ) }`, an option literal's payload (returned_option_call_payload_local).
// Closed: A returned literal's field from a call that lends it, and may lend it out of a local this frame drops on the way out, is copied as `^ ( g x )` copies it; a block field whose tail is such a call hands on the call's provenance (fld_eff_tt, g_blk_tail_eff; agora #189).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick → ?String {
    : W w ( mkw )
    ^ @ ?String { T ( gets w ) }
}

@ main → i {
    : ?String a ( pick )
    ?? a { T x → ( nurl_println_int ( string_len x ) ) F → ( nurl_println `none` ) }
    ^ 0
}
