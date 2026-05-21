// Test: stdlib/std/time.nu — calendar additions.
//
// time_make / is_leap_year / days_in_month / time_yday / time_cmp /
// time_eq|before|after / time_add_seconds|days / time_diff_seconds /
// time_format / time_parse_iso. Unix↔calendar values are deterministic
// (UTC). time_make / time_parse_iso return `! i ParseErr` (Unix secs);
// time_from_unix converts to a broken-down Time.

$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`

@ pi s label i v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int v ) )
    ( nurl_print `\n` )
}

@ ps s label String v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( string_data v ) )
    ( nurl_print `\n` )
    ( string_free v )
}

@ main → i {
    // ── time_from_unix + round-trip (1700000000 = 2023-11-14 UTC) ──
    : Time t ( time_from_unix 1700000000 )
    ( pi `year` . t year )
    ( pi `month` . t month )
    ( pi `day` . t day )
    ( pi `hour` . t hour )
    ( pi `min` . t min )
    ( pi `sec` . t sec )
    ( pi `wday` . t wday )
    ( pi `roundtrip` ( time_to_unix t ) )
    ( ps `iso` ( time_format_iso t ) )

    // ── leap year / days in month ──────────────────────────────────
    ( pi `leap2024` ? ( is_leap_year 2024 ) 1 0 )
    ( pi `leap2023` ? ( is_leap_year 2023 ) 1 0 )
    ( pi `leap2000` ? ( is_leap_year 2000 ) 1 0 )
    ( pi `leap1900` ? ( is_leap_year 1900 ) 1 0 )
    ( pi `feb2024` ( days_in_month 2024 2 ) )
    ( pi `feb2023` ( days_in_month 2023 2 ) )
    ( pi `apr2026` ( days_in_month 2026 4 ) )

    // ── time_make: valid + rejected ────────────────────────────────
    ?? ( time_make 2026 5 21 14 39 0 ) {
        T secs → {
            : Time tm ( time_from_unix secs )
            ( ps `make_ok` ( time_format_iso tm ) )
        }
        F e → ( nurl_print `make_ok=ERR\n` )
    }
    ?? ( time_make 2023 2 29 0 0 0 ) {
        T secs → ( nurl_print `feb29_2023=accepted\n` )
        F e → ( nurl_print `feb29_2023=rejected\n` )
    }
    ?? ( time_make 2026 13 1 0 0 0 ) {
        T secs → ( nurl_print `month13=accepted\n` )
        F e → ( nurl_print `month13=rejected\n` )
    }

    // ── day of year ────────────────────────────────────────────────
    ?? ( time_make 2024 12 31 0 0 0 ) {
        T secs → ( pi `yday_2024_12_31` ( time_yday ( time_from_unix secs ) ) )
        F e → {}
    }
    ?? ( time_make 2026 1 1 0 0 0 ) {
        T secs → ( pi `yday_2026_01_01` ( time_yday ( time_from_unix secs ) ) )
        F e → {}
    }

    // ── arithmetic + comparison ────────────────────────────────────
    : Time plus1d ( time_add_days t 1 )
    : Time plus90s ( time_add_seconds t 90 )
    ( pi `plus1d_unix` ( time_to_unix plus1d ) )
    ( pi `plus90s_unix` ( time_to_unix plus90s ) )
    ( pi `cmp_lt` ( time_cmp t plus1d ) )
    ( pi `cmp_gt` ( time_cmp plus1d t ) )
    ( pi `cmp_eq` ( time_cmp t t ) )
    ( pi `before` ? ( time_before t plus1d ) 1 0 )
    ( pi `after` ? ( time_after t plus1d ) 1 0 )
    ( pi `diff` ( time_diff_seconds plus1d t ) )

    // ── generic strftime-style format ──────────────────────────────
    ( ps `fmt` ( time_format t `%Y/%m/%d %H:%M:%S %a %b yday=%j %%done` ) )
    ( ps `fmt_full` ( time_format t `%A %B %d, %Y` ) )

    // ── ISO parse round-trip ───────────────────────────────────────
    ?? ( time_parse_iso `2023-11-14T22:13:20Z` ) {
        T secs → ( pi `parsed_unix` secs )
        F e → ( nurl_print `parse=ERR\n` )
    }
    ?? ( time_parse_iso `not-a-date` ) {
        T secs → ( nurl_print `badparse=accepted\n` )
        F e → ( nurl_print `badparse=rejected\n` )
    }

    ( nurl_print `done\n` )
    ^ 0
}
