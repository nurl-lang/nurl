// H844: agora #189 — the call field lending a parameter: still a lend, not copied (returned_literal_call_field_param).
// Closed: A returned literal's field from a call that lends it, and may lend it out of a local this frame drops on the way out, is copied as `^ ( g x )` copies it; a block field whose tail is such a call hands on the call's provenance (fld_eff_tt, g_blk_tail_eff; agora #189).
// main: accepted and ran clean (kept as a guard: the lend stays a lend).
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick W w → W { ^ @ W { ( gets w ) } }

@ main → i {
    : W w ( mkw )
    : W a ( pick w )
    ( nurl_println_int + ( string_len . a s ) ( string_len . w s ) )
    ^ 0
}
