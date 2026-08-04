// float_parse — nurl_fast_atof is correctly rounded, so text written by
// nurl_str_float reads back as the same double.
//
// The old parser accumulated digits in a double (`r = r*10 + d`, then
// `r += d * scale` with `scale *= 0.1`) and applied the exponent by
// binary powering of 10.0. Three consequences, all silent:
//   * ~1/3 of ordinary 6-9 significant-digit values landed 1+ ulp off;
//   * every value below ~1e-308 parsed as 0 — the multiplier overflowed
//     to inf and `r / inf` is 0;
//   * the largest finite double parsed as inf.
// `stdlib/ext/csv.nu` parses typed float columns with it, so a CSV
// round trip through NURL's own formatter did not return the values it
// was given. Pinned here: format, parse, compare BITS.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`

// format -> parse -> bit-compare
@ rt s label f x → v {
    : s txt ( nurl_str_float x )
    : f back ( nurl_fast_atof txt ( nurl_str_len txt ) )
    ( nurl_print label )
    ( nurl_print ` ` )
    ( nurl_print txt )
    ( nurl_print ? == ( f64_to_bits back ) ( f64_to_bits x ) ` ok` ` MISMATCH` )
    ( nurl_print `\n` )
    // no `nurl_free txt` here: `txt` is a tracked owned string and
    // auto-drop already releases it at scope exit. Freeing it by hand is
    // a double free that the runtime's small-block freelist hides — the
    // sanitized runner is what named it.
}

// parse a literal text and compare against the double the compiler
// produced for the same literal (LLVM parses it correctly rounded)
@ lit s txt f want → v {
    : f got ( nurl_fast_atof txt ( nurl_str_len txt ) )
    ( nurl_print txt )
    ( nurl_print ? == ( f64_to_bits got ) ( f64_to_bits want ) ` ok` ` MISMATCH` )
    ( nurl_print `\n` )
}

@ main → i {
    // ── round trips through the formatter ───────────────────────
    ( rt `third` / 1.0 3.0 )
    ( rt `pi` 3.141592653589793 )
    ( rt `sensor` 1234.5670000000001 )
    ( rt `frac` 0.30000000000000004 )
    ( rt `tiny` 5.0e-324 )  // smallest subnormal — parsed as 0 before
    ( rt `tiny2` 1.0e-320 )  // subnormal — parsed as 0 before
    ( rt `minnorm` 2.2250738585072014e-308 )
    ( rt `huge` 1.7976931348623157e308 )  // parsed as inf before
    ( rt `e23` 1.0e23 )
    ( rt `neg` -7.25 )

    // ── literals, against the compiler's own correctly-rounded parse ──
    ( lit `0.1` 0.1 )
    ( lit `0.30000000000000004` 0.30000000000000004 )
    ( lit `9007199254740993` 9007199254740993.0 )  // exact tie, rounds to even
    ( lit `9007199254740992` 9007199254740992.0 )
    ( lit `1e-320` 1.0e-320 )
    ( lit `2.2250738585072011e-308` 2.2250738585072011e-308 )  // subnormal edge
    ( lit `1.7976931348623157e308` 1.7976931348623157e308 )
    ( lit `123456789012345678901234567890` 1.2345678901234568e29 )  // 30 digits
    ( lit `-0.000000000000000000000000000001` -1.0e-30 )
    ( lit `1e309` ? T / 1.0 0.0 0.0 )  // overflows to inf
    ( lit `1e-400` 0.0 )  // underflows to zero

    // ── the digits BEYOND the ones we keep ───────────────────────
    // 807 significant digits whose first 800 are exactly the midpoint
    // between 5e-324 and 1e-323. The kept digits tie; only the dropped
    // ones decide it, so a parser that forgets them rounds to even
    // (down) where the true value rounds up.
    ( lit `741098468761869816264853189302332058547589703921487146638378523751013260905313127797949754542453988569694847043168576596389985065533909694598162194016172817189451069785467106791768725751773473155533077954085498096084575009581113730347476580968710095909754422710047573078097111189357848386756539987835030152280559340465937397917907387238682993958184816601691220194564999312897984113620624844986787135721803522090170239032857917325202205289740208029068540216066123755499834026713000358124864790413857434018755209015901725925471462961751341597749387185747378709616456389087181198412716730560170454930047052695901657637768849082679869725733665217655679410725087643375608460039849049721491174630855395563541886415131684784363130802375962957739830017089843750000000000000000000000000000000000000000000000001e-1124` 1.0e-323 )
    ^ 0
}
