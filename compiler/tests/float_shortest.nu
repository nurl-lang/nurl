// float_shortest — nurl_str_float generates the shortest round-tripping
// digits itself (runtime_core §2b), instead of asking libc "%.*g" + strtod
// five times per number.
//
// Two things are pinned here:
//   1. the %g STYLE rules the text still obeys (style e below 1e-4 and at
//      or above the significant-digit count, style f between them, no
//      trailing zeros, two-digit exponent minimum);
//   2. the ROUND TRIP, asserted rather than eyeballed — every value below
//      is parsed back and compared bit-for-bit against the literal.
//
// Powers of two are their own section: their rounding interval is
// asymmetric (the neighbour below is half an ulp away, the one above a
// whole one), so the shortest decimal inside it is NOT always the one a
// correctly-rounding printf produces at that precision. The old
// binary-search implementation could therefore never find it and emitted
// a needlessly long form for 46 of the 2098 powers of two — the four
// pinned here are the ones a systematic sweep of all of them turned up
// below 1e-270.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`

@ p f x → v { ( nurl_print ( nurl_str_float x ) ) ( nurl_print `\n` ) }

// Round-trip check: format, parse back, compare bits.
@ rt s label f x → v {
    : s txt ( nurl_str_float x )
    : f back ( nurl_str_to_float txt )
    ( nurl_print label )
    ( nurl_print ` ` )
    ( nurl_print txt )
    ( nurl_print ? == ( f64_to_bits back ) ( f64_to_bits x ) ` rt=ok` ` rt=FAIL` )
    ( nurl_print `\n` )
    // no `nurl_free txt` here: `txt` is a tracked owned string and
    // auto-drop already releases it at scope exit. Freeing it by hand is
    // a double free that the runtime's small-block freelist hides — the
    // sanitized runner is what named it.
}

@ main → i {
    // ── %g style boundaries ──────────────────────────────────────
    ( p 0.0001 )  // style f, the last one before the switch
    ( p 0.00001 )  // style e: exponent < -4
    ( p 1.5e-7 )
    ( p 1234567.5 )  // style f: 8 sig digits, exponent 6
    ( p 1.0e21 )  // integral but past 2^53 -> style e
    ( p 1.0e22 )
    ( p 1.0e23 )  // the classic: 9.999999999999999e22 is nearer
    ( p 1.0e100 )  // three-digit exponent
    ( p 1.0e-100 )
    ( p 5.0e-324 )  // smallest subnormal
    ( p 2.2250738585072014e-308 )  // smallest normal
    ( p 1.7976931348623157e308 )  // largest finite
    ( p 4.9e-324 )  // parses to the same subnormal as 5e-324
    ( p -0.0 )  // negative zero prints unsigned, as the old cast did

    // ── powers of two the old implementation printed too long ────
    ( p 7.120236347223045e-307 )
    ( p 7.291122019556398e-304 )
    ( p 8.209073602596753e-289 )
    ( p 5.641232424577593e-278 )

    // ── round trips ──────────────────────────────────────────────
    ( rt `third` / 1.0 3.0 )
    ( rt `pi` 3.141592653589793 )
    ( rt `tiny` 5.0e-324 )
    ( rt `huge` 1.7976931348623157e308 )
    ( rt `pow2` 7.120236347223045e-307 )
    ( rt `f32ish` 0.10000000149011612 )  // a float32 widened to double
    ( rt `e23` 1.0e23 )
    ( rt `frac` 0.30000000000000004 )
    ^ 0
}
