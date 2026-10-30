// nested_literal_call_field_local: agora #189 — the call field inside a literal nested in the returned one (nested_literal_call_field_local).
// Closed: A returned literal's field from a call that lends it, and may lend it out of a local this frame drops on the way out, is copied as `^ ( g x )` copies it; a block field whose tail is such a call hands on the call's provenance (fld_eff_tt, g_blk_tail_eff; agora #189).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h843 | agora #189: the call field inside a literal nested in the returned one
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

: P { W w i n }

@ pick → P {
    : W w ( mkw )
    ^ @ P { @ W { ( gets w ) } 1 }
}

@ main → i {
    : P a ( pick )
    ( nurl_println_int ( string_len . . a w s ) )
    ^ 0
}
