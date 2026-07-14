// match_arm_width_unify.nu — integer arms of different widths unify at the
// join, losslessly.
//
// `?? m { T x → x F → 0 }` over a ( Vec u ) is the natural spelling of "the
// byte, or zero" — and it used to be impossible: the u arm and the i literal
// could not share a phi, the match degraded silently to a statement, and the
// consumer got `undef` (in practice: a pointer printed as audio samples — a
// WebSocket PCM16 decoder heard an empty room forever).
//
// The join now extends every integer arm to 64 bits BY ITS OWN SIGNEDNESS
// (zext for unsigned and bool, sext for signed), which is exactly the
// bridging every store site already does — so u 200 comes through as 200,
// never −56, and the same-width case emits the same phi it always did. The
// language stops disagreeing with itself; float↔int stays an error
// (diag_match_mixed_arms).
//
// Expected output:
//   65
//   -7
//   200
//   -1
//   66
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ p i v → v {
    : String m ( string_new )
    ( string_push_int m v )
    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
    ( string_free m )
}

@ main → i {
    : ( Vec u ) d ( vec_new [u] )
    ( vec_push [u] d 65 )
    // u arm beside an i literal — the shape that used to yield undef
    : i a # i ?? ( vec_get [u] d 0 ) { T x → x F → 0 }
    ( p a )
    // the miss path takes the literal arm
    : i b # i ?? ( vec_get [u] d 9 ) { T x → x F → -7 }
    ( p b )
    // ternary, u arm taken: 200 must survive as 200 (zext), not −56 (sext)
    : ~ u small 200
    : i c ? T small 5
    ( p c )
    // ternary, signed arm taken through the same join
    : i e ? F small -1
    ( p e )
    // same-width arms are untouched — the phi they always got
    ( vec_push [u] d 66 )
    : ~ i f2 0
    ?? ( vec_get [u] d 1 ) { T x → { = f2 # i x } F → {} }
    ( p f2 )
    ( vec_free [u] d )
    ^ 0
}
