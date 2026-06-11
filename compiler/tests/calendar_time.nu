// calendar_time.nu — Phase 2 (calendar) acceptance test for
// stdlib/std/time.nu's `Time` API. Pure offline — no `now_seconds`
// calls so the snapshot is deterministic.
//
// Coverage:
//   * time_from_unix at the epoch (1970-01-01T00:00:00Z, Thursday).
//   * Common reference points: 2000-01-01 (millennium, Saturday),
//     2024-02-29 (leap day, Thursday), 1969-12-31 (last sec before
//     epoch, negative seconds path).
//   * time_to_unix round-trips: time_to_unix . time_from_unix t == t
//     for a few well-chosen `t`.
//   * time_format_iso: 24-byte fixed-width "YYYY-MM-DDTHH:MM:SSZ".
//   * time_format_http: RFC 7231 IMF-fixdate ("Wed, 06 May 2026 ...").
//   * time_parse_iso: round-trip the formatted ISO string.
//   * time_parse_iso: timezone offsets (+05:30, -08:00, fractional
//     seconds, lowercase 't' separator).
//   * Error paths for parse: too short, missing 'T', bad digits,
//     trailing garbage.

$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_int s prefix i n → v {
    ( nurl_print prefix )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

@ print_time s label Time t → v {
    ( nurl_print label )
    ( nurl_print ` ` )
    : String iso ( time_format_iso t )
    ( nurl_print ( string_data iso ) )
    ( string_free iso )
    ( nurl_print ` wday=` )
    ( nurl_print ( nurl_str_int . t wday ) )
    ( nurl_print `\n` )
}

// ── Reference points ─────────────────────────────────────────────────

@ run_reference → v {
    ( nurl_print `── reference points ──\n` )
    // 1970-01-01T00:00:00Z = unix 0 = Thursday (wday=4)
    : Time t0 ( time_from_unix 0 )
    ( print_time `epoch     ` t0 )

    // 2000-01-01T00:00:00Z = unix 946684800 = Saturday (wday=6)
    : Time t1 ( time_from_unix 946684800 )
    ( print_time `millennium` t1 )

    // 2024-02-29T12:34:56Z = unix 1709210096 = Thursday (wday=4)
    : Time t2 ( time_from_unix 1709210096 )
    ( print_time `leap day  ` t2 )

    // 1969-12-31T23:59:59Z = unix -1 = Wednesday (wday=3)
    : Time t3 ( time_from_unix -1 )
    ( print_time `pre-epoch ` t3 )
}

// ── Round-trip ───────────────────────────────────────────────────────

@ run_roundtrip → v {
    ( nurl_print `── round-trip ──\n` )
    : Time t1 ( time_from_unix 0 )
    ( println_int `  rt 0 → ` ( time_to_unix t1 ) )
    : Time t2 ( time_from_unix 1234567890 )
    ( println_int `  rt 1234567890 → ` ( time_to_unix t2 ) )
    : Time t3 ( time_from_unix 1709210096 )
    ( println_int `  rt 1709210096 → ` ( time_to_unix t3 ) )
    : Time t4 ( time_from_unix -1 )
    ( println_int `  rt -1 → ` ( time_to_unix t4 ) )
    : Time t5 ( time_from_unix -1000000 )
    ( println_int `  rt -1000000 → ` ( time_to_unix t5 ) )
}

// ── Format: HTTP IMF-fixdate ──────────────────────────────────────────

@ run_format_http → v {
    ( nurl_print `── format_http ──\n` )
    : Time t1 ( time_from_unix 0 )
    : String h1 ( time_format_http t1 )
    ( println_str `  epoch     = ` ( string_data h1 ) )
    ( string_free h1 )

    : Time t2 ( time_from_unix 1714987800 )
    : String h2 ( time_format_http t2 )
    ( println_str `  20240506  = ` ( string_data h2 ) )
    ( string_free h2 )
}

// ── Parse round-trip ─────────────────────────────────────────────────

@ run_parse_roundtrip → v {
    ( nurl_print `── parse round-trip ──\n` )
    // time_parse_iso yields the Unix timestamp; time_from_unix rebuilds
    // the broken-down Time.
    : !i ParseErr r ( time_parse_iso `2024-02-29T12:34:56Z` )
    ?? r {
        T secs → {
            ( println_int `  parsed → unix=` secs )
            ( print_time `  reform   ` ( time_from_unix secs ) )
        }
        F _ → ( nurl_print `  unexpected error\n` )
    }

    // Lowercase 't' separator + fractional seconds
    : !i ParseErr r2 ( time_parse_iso `2024-02-29t12:34:56.789Z` )
    ?? r2 {
        T secs → ( println_int `  lowert+frac → unix=` secs )
        F _ → ( nurl_print `  lowert+frac err\n` )
    }

    // +05:30 offset → expect 12:34:56 - 05:30 = 07:04:56 UTC
    : !i ParseErr r3 ( time_parse_iso `2024-02-29T12:34:56+05:30` )
    ?? r3 {
        T secs → ( println_int `  +05:30 → unix=` secs )
        F _ → ( nurl_print `  +05:30 err\n` )
    }

    // -08:00 offset → expect 12:34:56 + 08:00 = 20:34:56 UTC
    : !i ParseErr r4 ( time_parse_iso `2024-02-29T12:34:56-08:00` )
    ?? r4 {
        T secs → ( println_int `  -08:00 → unix=` secs )
        F _ → ( nurl_print `  -08:00 err\n` )
    }
}

// ── Error paths ──────────────────────────────────────────────────────

@ describe_err ParseErr e → s {
    ^ ?? e {
        Empty → `Empty`
        BadFormat → `BadFormat`
        TrailingGarbage → `TrailingGarbage`
        Overflow → `Overflow`
        Underflow → `Underflow`
    }
}

@ run_parse_errors → v {
    ( nurl_print `── parse errors ──\n` )
    : !i ParseErr e1 ( time_parse_iso `short` )
    ?? e1 {
        T _ → ( nurl_print `  short UNEXPECTED Some\n` )
        F e → ( println_str `  short → ` ( describe_err e ) )
    }
    : !i ParseErr e2 ( time_parse_iso `2024X02X29T12:34:56Z` )
    ?? e2 {
        T _ → ( nurl_print `  bad-sep UNEXPECTED Some\n` )
        F e → ( println_str `  bad-sep → ` ( describe_err e ) )
    }
    : !i ParseErr e3 ( time_parse_iso `2024-02-29 12:34:56Z` )
    ?? e3 {
        T _ → ( nurl_print `  space-sep UNEXPECTED Some\n` )
        F e → ( println_str `  space-sep → ` ( describe_err e ) )
    }
    : !i ParseErr e4 ( time_parse_iso `2024-02-29T12:34:56Zextra` )
    ?? e4 {
        T _ → ( nurl_print `  trailing UNEXPECTED Some\n` )
        F e → ( println_str `  trailing → ` ( describe_err e ) )
    }
}

@ main → i {
    ( run_reference )
    ( run_roundtrip )
    ( run_format_http )
    ( run_parse_roundtrip )
    ( run_parse_errors )
    ^ 0
}
