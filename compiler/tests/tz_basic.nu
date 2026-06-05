// Regression: std/time.nu §12b POSIX-TZ timezones / DST. Pins the exact
// 2026 DST transition instants for US Eastern (EST5EDT,M3.2.0,M11.1.0 →
// Mar 8 07:00 UTC / Nov 1 06:00 UTC) and EU Central (CET-1CEST,M3.5.0,
// M10.5.0/3 → Mar 29 01:00 UTC / Oct 25 01:00 UTC), plus offset/DST
// queries, local-civil conversion, a half-hour fixed zone, and ISO
// formatting with a numeric offset. Returns the failure count.

$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`

@ mk i Y i Mo i D i H i Mi i S → i {
    ^ ?? ( time_make Y Mo D H Mi S ) { T s → s F → -1 }
}

@ tzp s str → TimeZone {
    : !TimeZone ParseErr r ( tz_parse str )
    ^ ?? r { T z → z F → ( tz_utc ) }
}

@ expect_int i got i want s label → i {
    ? == got want { ^ 0 } {}
    ( nurl_print `  FAIL ` ) ( nurl_print label )
    ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
    ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
    ^ 1
}

@ expect_bool b got b want s label → i {
    ? == got want { ^ 0 } {}
    ( nurl_print `  FAIL bool ` ) ( nurl_print label ) ( nurl_print `\n` )
    ^ 1
}

@ expect_str s got s want s label → i {
    ? == 1 ( nurl_str_eq got want ) { ^ 0 } {}
    ( nurl_print `  FAIL str ` ) ( nurl_print label )
    ( nurl_print ` got "` ) ( nurl_print got ) ( nurl_print `" want "` ) ( nurl_print want ) ( nurl_print `"\n` )
    ^ 1
}

@ main → i {
    : ~ i fails 0

    // ── US Eastern ──
    : TimeZone us ( tzp `EST5EDT,M3.2.0,M11.1.0` )
    = fails + fails ( expect_int ( tz_offset_at us ( mk 2026 1 15 12 0 0 ) ) -18000 `us-winter-off` )
    = fails + fails ( expect_int ( tz_offset_at us ( mk 2026 7 1 12 0 0 ) ) -14400 `us-summer-off` )
    = fails + fails ( expect_bool ( tz_is_dst us ( mk 2026 1 15 12 0 0 ) ) F `us-winter-dst` )
    = fails + fails ( expect_bool ( tz_is_dst us ( mk 2026 7 1 12 0 0 ) ) T `us-summer-dst` )

    // Exact spring-forward instant: Mar 8 2026 07:00 UTC.
    : i us_start ( mk 2026 3 8 7 0 0 )
    = fails + fails ( expect_bool ( tz_is_dst us - us_start 1 ) F `us-pre-start` )
    = fails + fails ( expect_bool ( tz_is_dst us us_start ) T `us-at-start` )
    // Exact fall-back instant: Nov 1 2026 06:00 UTC.
    : i us_end ( mk 2026 11 1 6 0 0 )
    = fails + fails ( expect_bool ( tz_is_dst us - us_end 1 ) T `us-pre-end` )
    = fails + fails ( expect_bool ( tz_is_dst us us_end ) F `us-at-end` )

    // Local civil fields: 2026-07-01 12:00 UTC → 08:00 EDT.
    : Time ul ( time_from_unix_tz ( mk 2026 7 1 12 0 0 ) us )
    = fails + fails ( expect_int . ul hour 8 `us-local-hour` )
    = fails + fails ( expect_int . ul day 1 `us-local-day` )

    // Round-trip: local wall-clock 08:00 EDT on 2026-07-01 → UTC noon.
    : Time wall ( time_from_unix ( mk 2026 7 1 8 0 0 ) )
    = fails + fails ( expect_int ( time_to_unix_tz wall us ) ( mk 2026 7 1 12 0 0 ) `us-to-unix` )

    // ── EU Central (last-Sunday rules + /3 end time) ──
    : TimeZone eu ( tzp `CET-1CEST,M3.5.0,M10.5.0/3` )
    = fails + fails ( expect_int ( tz_offset_at eu ( mk 2026 1 15 12 0 0 ) ) 3600 `eu-winter-off` )
    = fails + fails ( expect_int ( tz_offset_at eu ( mk 2026 7 1 12 0 0 ) ) 7200 `eu-summer-off` )
    : i eu_start ( mk 2026 3 29 1 0 0 )
    = fails + fails ( expect_bool ( tz_is_dst eu - eu_start 1 ) F `eu-pre-start` )
    = fails + fails ( expect_bool ( tz_is_dst eu eu_start ) T `eu-at-start` )
    : i eu_end ( mk 2026 10 25 1 0 0 )
    = fails + fails ( expect_bool ( tz_is_dst eu - eu_end 1 ) T `eu-pre-end` )
    = fails + fails ( expect_bool ( tz_is_dst eu eu_end ) F `eu-at-end` )

    // ── Fixed half-hour zone, no DST (India, +05:30) ──
    : TimeZone ist ( tzp `IST-5:30` )
    = fails + fails ( expect_int ( tz_offset_at ist ( mk 2026 6 1 0 0 0 ) ) 19800 `ist-off` )
    = fails + fails ( expect_bool ( tz_is_dst ist ( mk 2026 6 1 0 0 0 ) ) F `ist-dst` )

    // tz_fixed / tz_utc
    = fails + fails ( expect_int ( tz_offset_at ( tz_fixed -28800 ) 0 ) -28800 `fixed` )
    = fails + fails ( expect_int ( tz_offset_at ( tz_utc ) 0 ) 0 `utc` )

    // ── ISO formatting with offset ──
    : String s1 ( time_format_iso_tz ( mk 2026 7 1 12 0 0 ) us )
    = fails + fails ( expect_str ( string_data s1 ) `2026-07-01T08:00:00-04:00` `iso-edt` )
    ( string_free s1 )
    : String s2 ( time_format_iso_tz ( mk 2026 1 15 12 0 0 ) us )
    = fails + fails ( expect_str ( string_data s2 ) `2026-01-15T07:00:00-05:00` `iso-est` )
    ( string_free s2 )
    : String s3 ( time_format_iso_tz ( mk 2026 6 1 6 30 0 ) ist )
    = fails + fails ( expect_str ( string_data s3 ) `2026-06-01T12:00:00+05:30` `iso-ist` )
    ( string_free s3 )

    // Malformed TZ string must be rejected.
    : !TimeZone ParseErr bad ( tz_parse `EST5EDT,Junk,Nope` )
    ?? bad { T _ → { ( nurl_print `  FAIL accepted bad rule\n` ) = fails + fails 1 } F → {} }

    ? == fails 0 { ( nurl_print `tz: all checks PASS\n` ) } {
        ( nurl_print `tz: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
