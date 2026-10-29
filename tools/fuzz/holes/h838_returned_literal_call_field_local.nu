// H838: agora #189 — `^ @ W { ( gets w ) }`, a returned literal's field from a call lending the local `w` (returned_literal_call_field_local).
// Closed: A returned literal's field from a call that lends it, and may lend it out of a local this frame drops on the way out, is copied as `^ ( g x )` copies it; a block field whose tail is such a call hands on the call's provenance (fld_eff_tt, g_blk_tail_eff; agora #189).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ pick → W {
    : W w ( mkw )
    ^ @ W { ( gets w ) }
}

@ main → i {
    : W a ( pick )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
