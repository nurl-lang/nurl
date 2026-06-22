// trace.nu — offline tests for stdlib/std/trace.nu: the W3C traceparent
// format/parse round trip, hex rendering, and the current-context globals.
// Deterministic (fixed ids, no randomness).

$ `stdlib/core/string.nu`
$ `stdlib/std/trace.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `true\n` `false\n` ) }

@ main → i {
    // ── hex rendering ────────────────────────────────────────────
    : String hx ( trace_hex16 255 )
    ( nurl_print `hex(255)=` ) ( nurl_print ( string_data hx ) ) ( nurl_print `\n` )
    ( string_free hx )

    // ── format → parse round trip ────────────────────────────────
    : i tid 305419896  // 0x12345678
    : i sid 3203386110  // 0xBEEFCAFE
    : String tp ( traceparent_format tid sid )
    ( nurl_print `tp=` ) ( nurl_print ( string_data tp ) ) ( nurl_print `\n` )
    : TraceParsed p ( traceparent_parse ( string_data tp ) )
    ( string_free tp )
    ( nurl_print `parsed ok=` ) ( nurl_print_int . p ok )
    ( nurl_print ` trace=` ) ( nurl_print_int . p trace )
    ( nurl_print ` span=` ) ( nurl_print_int . p span ) ( nurl_print `\n` )
    ( pb `round-trip: ` & == . p trace tid == . p span sid )

    // ── current-context globals ──────────────────────────────────
    ( pb `active (fresh): ` ( trace_active ) )
    ( trace_set tid sid )
    ( pb `active (set): ` ( trace_active ) )
    ( nurl_print `cur trace=` ) ( nurl_print_int ( trace_current_trace ) ) ( nurl_print `\n` )
    ( trace_clear )
    ( pb `active (cleared): ` ( trace_active ) )

    // ── high-bit-set id (a NEGATIVE i64) must still round-trip ───
    : i big - 0 1  // 0xffffffffffffffff
    : String tpb ( traceparent_format big big )
    ( nurl_print `tp(big)=` ) ( nurl_print ( string_data tpb ) ) ( nurl_print `\n` )
    : TraceParsed hp ( traceparent_parse ( string_data tpb ) )
    ( string_free tpb )
    ( pb `high-bit round-trip: ` & & == . hp ok 1 == . hp trace big == . hp span big )

    // ── malformed header rejected ────────────────────────────────
    : TraceParsed bp ( traceparent_parse `not-a-traceparent` )
    ( nurl_print `bad ok=` ) ( nurl_print_int . bp ok ) ( nurl_print `\n` )
    ^ 0
}
