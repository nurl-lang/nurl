// anomaly/imptime.nu — where a file keeps its clock, and how to read it.
//
// A stream stamps every point at the moment it arrives. A file has no such
// moment: its clock is in the data — a `timestamp` column, an ISO string
// under some other name, a Unix number, or a date spread over `Vuosi`,
// `Kuukausi`, `Päivä` and `Aika` the way a weather-service export writes
// it. This file reads all of those, best effort, and says which one it
// read, so the person importing can confirm or correct the guess before a
// single row lands.
//
// Two operations:
//
//   import_inspect      parsed rows → JSON: every column with what its
//                       values look like, and a proposal for the time —
//                       one column, a set of part columns, or nothing.
//   import_time_apply   rows + a plan → every row gets `timestamp` (Unix
//                       seconds) from the plan; the source columns are
//                       dropped so a year or a clock does not become a
//                       feature; and, on request, a `time` ISO string is
//                       left behind for the calendar features (hour, day,
//                       month, weekday) the preprocessing layer derives.
//
// Naive stamps — a clock without an offset, which is what a database
// TIMESTAMP WITHOUT TIME ZONE, a spreadsheet and a weather export all
// write — are read in the timezone the caller names, defaulting to the
// server's local one: the file came from the place the service runs.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/time.nu`

// The caller's "use the server's local zone" sentinel for a tz offset.
: i ANOM_TZ_LOCAL -1000000

// Rows looked at when describing a file. A million-row file is described
// by its first five thousand; the plan then applies to all of them.
: i ANOM_INSPECT_ROWS 5000

// What one cell turned out to be.
: i STAMP_NONE 0
: i STAMP_DATETIME 1  // a date and a time of day
: i STAMP_DATE 2  // a date alone (midnight)
: i STAMP_UNIX 3  // a Unix number — seconds, ms, µs or ns by magnitude
: i STAMP_CLOCK 4  // a time of day alone, HH:MM[:SS]

// `secs` is Unix seconds when `zoned` (the text carried an offset, or was
// a Unix number); otherwise the civil fields read as if they were UTC, for
// the caller to shift into the zone it was told. For STAMP_CLOCK it is
// seconds after midnight.
: ImpStamp {
    i kind
    i secs
    b zoned
}

@ __it_none → ImpStamp { ^ @ ImpStamp { STAMP_NONE 0 F } }

// ── Reading one cell ──────────────────────────────────────────────────

: __ItNum { i val i len }

// Up to `max` digits at `start`; len 0 when there is none.
@ __it_digits s p i n i start i max → __ItNum {
    : ~ i acc 0
    : ~ i k 0
    : ~ b go T
    ~ & go & < k max < + start k n {
        : i c ( nurl_str_at p n + start k )
        ? & >= c 48 <= c 57 { = acc + * acc 10 - c 48 = k + k 1 } { = go F }
    }
    ^ @ __ItNum { acc k }
}

@ __it_is_digit s p i n i k → b {
    ? >= k n { ^ F } {}
    : i c ( nurl_str_at p n k )
    ^ & >= c 48 <= c 57
}

@ __it_skip_ws s p i n i k → i {
    : ~ i j k
    ~ & < j n | == ( nurl_str_at p n j ) 32 == ( nurl_str_at p n j ) 9 { = j + j 1 }
    ^ j
}

// A Unix number by magnitude: seconds (10 digits or so), milli-, micro-
// or nanoseconds. Anything below 1e8 (1973) is a number, not a clock.
@ __it_unix_of f x → ImpStamp {
    : f ax ? < x 0.0 - 0.0 x x
    ? < ax 100000000.0 { ^ ( __it_none ) } {}
    ? < ax 100000000000.0 { ^ @ ImpStamp { STAMP_UNIX # i x T } } {}
    ? < ax 100000000000000.0 { ^ @ ImpStamp { STAMP_UNIX # i / x 1000.0 T } } {}
    ? < ax 100000000000000000.0 { ^ @ ImpStamp { STAMP_UNIX # i / x 1000000.0 T } } {}
    ^ @ ImpStamp { STAMP_UNIX # i / x 1000000000.0 T }
}

// A whole-number time of day at k: HH:MM[:SS[.frac]]. Returns the
// seconds after midnight and where it stopped, or len 0.
@ __it_clock_at s p i n i k → __ItNum {
    : __ItNum h ( __it_digits p n k 2 )
    ? | == . h len 0 > . h val 23 { ^ @ __ItNum { 0 0 } } {}
    : i k1 + k . h len
    ? & < k1 n == ( nurl_str_at p n k1 ) 58 {} { ^ @ __ItNum { 0 0 } }
    : __ItNum m ( __it_digits p n + k1 1 2 )
    ? | != . m len 2 > . m val 59 { ^ @ __ItNum { 0 0 } } {}
    : ~ i k2 + + k1 1 2
    : ~ i secs + * . h val 3600 * . m val 60
    ? & < k2 n == ( nurl_str_at p n k2 ) 58 {
        : __ItNum sec ( __it_digits p n + k2 1 2 )
        ? & == . sec len 2 <= . sec val 60 {
            = secs + secs . sec val
            = k2 + + k2 1 2
            ? & < k2 n == ( nurl_str_at p n k2 ) 46 {
                = k2 + k2 1
                ~ ( __it_is_digit p n k2 ) { = k2 + k2 1 }
            } {}
        } {}
    } {}
    ^ @ __ItNum { secs - k2 k }
}

// A zone suffix at k: Z, UTC, GMT, ±HH[:MM], ±HHMM. `val` is the offset
// in seconds east; `len` 0 means none was there.
@ __it_zone_at s p i n i k → __ItNum {
    ? >= k n { ^ @ __ItNum { 0 0 } } {}
    : i c ( nurl_str_at p n k )
    ? | == c 90 == c 122 { ^ @ __ItNum { 0 1 } } {}
    ? <= + k 3 n {
        : i c1 ( nurl_str_at p n + k 1 )
        : i c2 ( nurl_str_at p n + k 2 )
        ? & & == c 85 == c1 84 == c2 67 { ^ @ __ItNum { 0 3 } } {}  // UTC
        ? & & == c 71 == c1 77 == c2 84 { ^ @ __ItNum { 0 3 } } {}  // GMT
    } {}
    ? | == c 43 == c 45 {
        : i sign ? == c 45 -1 1
        : __ItNum hh ( __it_digits p n + k 1 2 )
        ? != . hh len 2 { ^ @ __ItNum { 0 0 } } {}
        : ~ i j + + k 1 2
        : ~ i mins 0
        ? & < j n == ( nurl_str_at p n j ) 58 { = j + j 1 } {}
        : __ItNum mm ( __it_digits p n j 2 )
        ? == . mm len 2 { = mins . mm val = j + j 2 } {}
        ^ @ __ItNum { * sign + * . hh val 3600 * mins 60 - j k }
    } {}
    ^ @ __ItNum { 0 0 }
}

// After a date ending at k: optional [T| ]HH:MM[:SS], optional zone,
// then nothing but spaces. Returns the stamp, or NONE when the tail is
// not a time.
@ __it_tail s p i n i k i y i mo i d → ImpStamp {
    : !i ParseErr mk ( time_make y mo d 0 0 0 )
    : ~ i base 0
    ?? mk { T x → { = base x } F _ → { ^ ( __it_none ) } }
    : ~ i j k
    : ~ b had_time F
    : ~ i tod 0
    ? < j n {
        : i c ( nurl_str_at p n j )
        ? | | == c 84 == c 116 == c 32 {
            = j ( __it_skip_ws p n + j 1 )
            : __ItNum cl ( __it_clock_at p n j )
            ? > . cl len 0 { = tod . cl val = j + j . cl len = had_time T } {
                // "2026-08-29 " with nothing after it is still a date.
                ? == c 32 {} { ^ ( __it_none ) }
            }
        } {}
    } {}
    = j ( __it_skip_ws p n j )
    : __ItNum z ( __it_zone_at p n j )
    = j + j . z len
    = j ( __it_skip_ws p n j )
    ? == j n {} { ^ ( __it_none ) }
    : i secs + base tod
    ? > . z len 0 { ^ @ ImpStamp { ? had_time STAMP_DATETIME STAMP_DATE - secs . z val T } } {}
    ^ @ ImpStamp { ? had_time STAMP_DATETIME STAMP_DATE secs F }
}

// One cell of text as a stamp. Formats, in the order they are tried:
//
//   2026-08-29T00:10:00Z, 2026-08-29 00:10:00+03:00, 2026-08-29 00:10,
//   2026-08-29                          ISO 8601 / RFC 3339, SQL TIMESTAMP
//                                       with or without a zone, date alone
//   2026/08/29 00:10                    the same with slashes
//   29.8.2026 00:10, 29.8.2026          day first — dots are European
//   29/08/2026, 08/29/2026              slashes: day first unless the second
//                                       number cannot be a month
//   20260829, 20260829T001000           compact
//   1756422600, 1756422600000           Unix seconds / ms / µs / ns
//   Sat, 29 Aug 2026 00:10:00 +0300     RFC 2822 and HTTP dates
//   00:10, 00:10:00                     a time of day alone (STAMP_CLOCK)
@ imp_stamp_of_text s raw → ImpStamp {
    : String t0 ( string_from raw )
    : String t ( string_trim t0 )
    ( string_free t0 )
    : s p ( string_data t )
    : i n ( nurl_str_len p )
    ? > n 0 {} { ( string_free t ) ^ ( __it_none ) }

    // All digits: a compact date, or a Unix number.
    : ~ i nd 0
    ~ & < nd n ( __it_is_digit p n nd ) { = nd + nd 1 }
    ? == nd n {
        ? == n 8 {
            : __ItNum y ( __it_digits p n 0 4 )
            : __ItNum mo ( __it_digits p n 4 2 )
            : __ItNum d ( __it_digits p n 6 2 )
            : ImpStamp st ( __it_tail p n 8 . y val . mo val . d val )
            ( string_free t )
            ^ st
        } {}
        ? == n 14 {
            : __ItNum y ( __it_digits p n 0 4 )
            : __ItNum mo ( __it_digits p n 4 2 )
            : __ItNum d ( __it_digits p n 6 2 )
            : __ItNum hh ( __it_digits p n 8 2 )
            : __ItNum mi ( __it_digits p n 10 2 )
            : __ItNum ss ( __it_digits p n 12 2 )
            : !i ParseErr mk ( time_make . y val . mo val . d val . hh val . mi val . ss val )
            ( string_free t )
            ?? mk { T x → { ^ @ ImpStamp { STAMP_DATETIME x F } } F _ → { ^ ( __it_none ) } }
        } {}
    } {}
    // Any other number is Unix seconds or nothing: "29.8" is not a date.
    ?? ( string_to_float t ) {
        T x → {
            : ImpStamp u ( __it_unix_of x )
            ? > . u kind 0 { ( string_free t ) ^ u } {}
        }
        F → {}
    }

    // 8 digits with a T: 20260829T0010[00]
    ? & > n 9 & == nd 8 | == ( nurl_str_at p n 8 ) 84 == ( nurl_str_at p n 8 ) 116 {
        : __ItNum y ( __it_digits p n 0 4 )
        : __ItNum mo ( __it_digits p n 4 2 )
        : __ItNum d ( __it_digits p n 6 2 )
        : __ItNum hh ( __it_digits p n 9 2 )
        : __ItNum mi ( __it_digits p n 11 2 )
        : __ItNum ss ( __it_digits p n 13 2 )
        : !i ParseErr mk ( time_make . y val . mo val . d val . hh val . mi val ? == . ss len 2 . ss val 0 )
        ?? mk {
            T x → {
                : i j ( __it_skip_ws p n ? == . ss len 2 15 13 )
                : __ItNum z ( __it_zone_at p n j )
                ? == ( __it_skip_ws p n + j . z len ) n {
                    ( string_free t )
                    ^ @ ImpStamp { STAMP_DATETIME ? > . z len 0 - x . z val x > . z len 0 }
                } {}
            }
            F _ → {}
        }
    } {}

    // Year first: YYYY-MM-DD or YYYY/MM/DD.
    : __ItNum a ( __it_digits p n 0 4 )
    ? & == . a len 4 < 4 n {
        : i sep ( nurl_str_at p n 4 )
        ? | == sep 45 == sep 47 {
            : __ItNum mo ( __it_digits p n 5 2 )
            : i k1 + 5 . mo len
            ? & > . mo len 0 & < k1 n == ( nurl_str_at p n k1 ) sep {
                : __ItNum d ( __it_digits p n + k1 1 2 )
                ? > . d len 0 {
                    : ImpStamp st ( __it_tail p n + + k1 1 . d len . a val . mo val . d val )
                    ? > . st kind 0 { ( string_free t ) ^ st } {}
                } {}
            } {}
        } {}
    } {}

    // Day first: D.M.YYYY, D/M/YYYY, D-M-YYYY (and M/D/YYYY when D > 12).
    : __ItNum b1 ( __it_digits p n 0 2 )
    ? & > . b1 len 0 < . b1 len n {
        : i sep ( nurl_str_at p n . b1 len )
        ? | | == sep 46 == sep 47 == sep 45 {
            : __ItNum b2 ( __it_digits p n + . b1 len 1 2 )
            : i k2 + + . b1 len 1 . b2 len
            ? & > . b2 len 0 & < k2 n == ( nurl_str_at p n k2 ) sep {
                : __ItNum y ( __it_digits p n + k2 1 4 )
                ? == . y len 4 {
                    : ~ i d . b1 val
                    : ~ i mo . b2 val
                    // 08/29/2026: the second number cannot be a month, so
                    // the file is month-first.
                    ? & == sep 47 & > mo 12 <= d 12 { = d . b2 val = mo . b1 val } {}
                    : ImpStamp st ( __it_tail p n + + k2 1 4 . y val mo d )
                    ? > . st kind 0 { ( string_free t ) ^ st } {}
                } {}
            } {}
        } {}
    } {}

    // A time of day alone.
    : __ItNum cl ( __it_clock_at p n 0 )
    ? & > . cl len 0 == ( __it_skip_ws p n . cl len ) n {
        ( string_free t )
        ^ @ ImpStamp { STAMP_CLOCK . cl val F }
    } {}

    // The mail and HTTP spellings, which carry their own zone.
    : !i ParseErr r1 ( rfc2822_parse p )
    ?? r1 { T x → { ( string_free t ) ^ @ ImpStamp { STAMP_DATETIME x T } } F _ → {} }
    : !i ParseErr r2 ( http_date_parse p )
    ?? r2 { T x → { ( string_free t ) ^ @ ImpStamp { STAMP_DATETIME x T } } F _ → {} }
    ( string_free t )
    ^ ( __it_none )
}

// One JSON cell as a stamp: a number is Unix, a string is text.
@ imp_stamp_of Json v → ImpStamp {
    ? ( json_is_num v ) {
        ?? ( json_num_as_f v ) { T x → { ^ ( __it_unix_of x ) } F _ → {} }
        ^ ( __it_none )
    } {}
    ? ( json_is_str v ) { ^ ( imp_stamp_of_text ( json_str_data v ) ) } {}
    ^ ( __it_none )
}

// Shift a naive stamp into the zone: `tz` seconds east, or ANOM_TZ_LOCAL
// for the server's own zone at that moment.
@ __it_finish i naive b zoned i tz → i {
    ? zoned { ^ naive } {}
    ? == tz ANOM_TZ_LOCAL { ^ - naive ( tz_offset naive ) } {}
    ^ - naive tz
}

// The offset that applies to a Unix instant under `tz`.
@ __it_off_at i utc i tz → i {
    ? == tz ANOM_TZ_LOCAL { ^ ( tz_offset utc ) } {}
    ^ tz
}

// A `tz` spelling: "local", "utc", "Z", "+03:00", "+0300", "+03", or a
// number of seconds east. Unreadable → local.
@ imp_tz_of Json spec → i {
    ?? ( json_obj_get spec `tz` ) {
        T v → {
            ? ( json_is_num v ) { ^ ( json_as_int v ) } {}
            ? ( json_is_str v ) {
                : s z ( json_str_data v )
                ? | == ( nurl_str_eq z `local` ) 1 == ( nurl_str_len z ) 0 { ^ ANOM_TZ_LOCAL } {}
                ? | | == ( nurl_str_eq z `utc` ) 1 == ( nurl_str_eq z `UTC` ) 1 == ( nurl_str_eq z `Z` ) 1 { ^ 0 } {}
                : i n ( nurl_str_len z )
                : __ItNum zo ( __it_zone_at z n 0 )
                ? & > . zo len 0 == . zo len n { ^ . zo val } {}
            } {}
        }
        F _ → {}
    }
    ^ ANOM_TZ_LOCAL
}

// ── Column names ──────────────────────────────────────────────────────

// Lowercase, with any bracketed unit removed and the edges trimmed:
// "Aika [Paikallinen aika]" → "aika", "Temp (°C)" → "temp".
@ __it_norm_name s raw → String {
    : String lo0 ( string_from raw )
    : String lo ( string_to_lower lo0 )
    ( string_free lo0 )
    : String out ( string_new )
    : s p ( string_data lo )
    : i n ( nurl_str_len p )
    : ~ i depth 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at p n k )
        ? | == c 91 == c 40 { = depth + depth 1 } {
            ? | == c 93 == c 41 { ? > depth 0 { = depth - depth 1 } {} } {
                ? == depth 0 { ( string_push_char out c ) } {}
            }
        }
        = k + k 1
    }
    ( string_free lo )
    : String tr ( string_trim out )
    ( string_free out )
    ^ tr
}

// Does `name` (normalised) mean one of the roles? 2 = a strong name
// nobody would use for anything else, 1 = a short one that might be
// "minimum" or "seconds" or a coordinate, 0 = no.
: i ROLE_STAMP 0
: i ROLE_YEAR 1
: i ROLE_MONTH 2
: i ROLE_DAY 3
: i ROLE_HOUR 4
: i ROLE_MINUTE 5
: i ROLE_SECOND 6
: i ROLE_DATE 7
: i ROLE_CLOCK 8

@ __it_in s name s list → b {
    // `list` is `|a|b|c|`; look for `|name|`.
    : String needle ( string_from `|` )
    ( string_push_str needle name )
    ( string_push_str needle `|` )
    : i r ( nurl_str_find list ( string_data needle ) )
    ( string_free needle )
    ^ >= r 0
}

@ __it_role_strength s name i role → i {
    ? == role ROLE_STAMP {
        ? ( __it_in name `|timestamp|datetime|date_time|date-time|time_stamp|aikaleima|ajanhetki|hetki|created_at|updated_at|recorded_at|measured_at|observed_at|event_time|eventtime|logged_at|` ) { ^ 2 } {}
        ? ( __it_in name `|time|date|ts|aika|pvm|päivämäärä|paivamaara|kello|klo|created|updated|recorded|epoch|unix|unixtime|unix_time|when|t|_time|datum|zeit|tid|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_DATE {
        ? ( __it_in name `|date|pvm|päivämäärä|paivamaara|päivä|datum|day_date|` ) { ^ 2 } {}
        ^ 0
    } {}
    ? == role ROLE_CLOCK {
        ? ( __it_in name `|time|aika|kello|klo|clock|time_of_day|tod|` ) { ^ 2 } {}
        ^ 0
    } {}
    ? == role ROLE_YEAR {
        ? ( __it_in name `|year|vuosi|yyyy|` ) { ^ 2 } {}
        ? ( __it_in name `|yr|y|yy|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_MONTH {
        ? ( __it_in name `|month|kuukausi|` ) { ^ 2 } {}
        ? ( __it_in name `|mon|mm|m|kk|mo|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_DAY {
        ? ( __it_in name `|day|päivä|paiva|dayofmonth|day_of_month|` ) { ^ 2 } {}
        ? ( __it_in name `|dd|d|pv|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_HOUR {
        ? ( __it_in name `|hour|hours|tunti|` ) { ^ 2 } {}
        ? ( __it_in name `|hh|h|hr|hrs|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_MINUTE {
        ? ( __it_in name `|minute|minutes|minuutti|` ) { ^ 2 } {}
        ? ( __it_in name `|min|mins|mi|mm|` ) { ^ 1 } {}
        ^ 0
    } {}
    ? == role ROLE_SECOND {
        ? ( __it_in name `|second|seconds|sekunti|` ) { ^ 2 } {}
        ? ( __it_in name `|sec|secs|ss|s|` ) { ^ 1 } {}
        ^ 0
    } {}
    ^ 0
}

// ── Describing the columns ────────────────────────────────────────────

: ImpCol {
    String cname
    String norm
    i filled
    i n_num
    i n_text
    i n_dt  // text that reads as a date and time
    i n_date  // text that reads as a date alone
    i n_clock  // text that reads as a time of day alone
    i n_unix  // numbers that could be Unix stamps
    i n_year  // numbers 1900..2100
    i n_month  // numbers 1..12
    i n_day  // numbers 1..31
    i n_hour  // numbers 0..23
    i n_minsec  // numbers 0..59
    String sample
}

@ __it_col_free ImpCol c → v {
    ( string_free . c cname )
    ( string_free . c norm )
    ( string_free . c sample )
}

@ __it_col_find ( Vec ImpCol ) cols s name → i {
    : i n ( vec_len [ImpCol] cols )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [ImpCol] cols k ) {
            T c → { ? == ( nurl_str_eq ( string_data . c cname ) name ) 1 { ^ k } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ -1
}

@ __it_col_new s name → ImpCol {
    ^ @ ImpCol { ( string_from name ) ( __it_norm_name name ) 0 0 0 0 0 0 0 0 0 0 0 0 ( string_new ) }
}

// Count one cell into its column (a copy; the caller stores it back).
@ __it_col_add ImpCol c0 Json v → ImpCol {
    : ~ ImpCol c c0
    = . c filled + . c filled 1
    ? == ( string_len . c sample ) 0 {
        ( string_free . c sample )
        ? ( json_is_str v ) { = . c sample ( string_from ( json_str_data v ) ) } { = . c sample ( json_stringify v ) }
    } {}
    ? ( json_is_num v ) {
        = . c n_num + . c n_num 1
        ?? ( json_num_as_f v ) {
            T x → {
                : ImpStamp u ( __it_unix_of x )
                ? > . u kind 0 { = . c n_unix + . c n_unix 1 } {}
                : b whole == x # f # i x
                ? & whole & >= x 1900.0 <= x 2100.0 { = . c n_year + . c n_year 1 } {}
                ? & whole & >= x 1.0 <= x 12.0 { = . c n_month + . c n_month 1 } {}
                ? & whole & >= x 1.0 <= x 31.0 { = . c n_day + . c n_day 1 } {}
                ? & whole & >= x 0.0 <= x 23.0 { = . c n_hour + . c n_hour 1 } {}
                ? & whole & >= x 0.0 <= x 59.0 { = . c n_minsec + . c n_minsec 1 } {}
            }
            F _ → {}
        }
        ^ c
    } {}
    ? ( json_is_str v ) {
        = . c n_text + . c n_text 1
        : ImpStamp st ( imp_stamp_of_text ( json_str_data v ) )
        ? == . st kind STAMP_DATETIME { = . c n_dt + . c n_dt 1 } {}
        ? == . st kind STAMP_DATE { = . c n_date + . c n_date 1 } {}
        ? == . st kind STAMP_CLOCK { = . c n_clock + . c n_clock 1 } {}
        ? == . st kind STAMP_UNIX { = . c n_unix + . c n_unix 1 } {}
    } {}
    ^ c
}

// Nine in ten filled cells is the bar for "this column IS that": a few
// blanks or a "-" placeholder must not hide a clock.
@ __it_mostly i part i whole → b {
    ? <= whole 0 { ^ F } {}
    ^ >= * part 10 * whole 9
}

// What a column's values look like, as one word.
@ __it_col_kind ImpCol c → s {
    ? <= . c filled 0 { ^ `empty` } {}
    ? ( __it_mostly . c n_dt . c filled ) { ^ `datetime` } {}
    ? ( __it_mostly . c n_date . c filled ) { ^ `date` } {}
    ? ( __it_mostly . c n_clock . c filled ) { ^ `clock` } {}
    ? ( __it_mostly . c n_unix . c filled ) { ^ `unix` } {}
    ? == . c n_num . c filled { ^ `number` } {}
    ? == . c n_text . c filled { ^ `text` } {}
    ^ `mixed`
}

@ __it_describe ( Vec Json ) rows → ( Vec ImpCol ) {
    : ( Vec ImpCol ) cols ( vec_new [ImpCol] )
    : i n ( vec_len [Json] rows )
    : i lim ? < n ANOM_INSPECT_ROWS n ANOM_INSPECT_ROWS
    : ~ i k 0
    ~ < k lim {
        ?? ( vec_get [Json] rows k ) {
            T row → {
                : ( Vec String ) keys ( json_obj_keys row )
                : i nk ( vec_len [String] keys )
                : ~ i q 0
                ~ < q nk {
                    ?? ( vec_get [String] keys q ) {
                        T key → {
                            : ~ i ci ( __it_col_find cols ( string_data key ) )
                            ? < ci 0 {
                                = ci ( vec_len [ImpCol] cols )
                                ( vec_push [ImpCol] cols ( __it_col_new ( string_data key ) ) )
                            } {}
                            ?? ( json_obj_get row ( string_data key ) ) {
                                T v → {
                                    ?? ( vec_get [ImpCol] cols ci ) {
                                        T c → {
                                            : b _s ( vec_set [ImpCol] cols ci ( __it_col_add c v ) )
                                        }
                                        F _ → {}
                                    }
                                }
                                F _ → {}
                            }
                        }
                        F _ → {}
                    }
                    = q + q 1
                }
                ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ cols
}

// ── The proposal ──────────────────────────────────────────────────────

// The best column for a role: the strongest name whose values fit, or,
// for the value-defined roles (clock, date, stamp), the best-named column
// whose values ARE that. Returns the index, or -1.
@ __it_best ( Vec ImpCol ) cols i role → i {
    : i n ( vec_len [ImpCol] cols )
    : ~ i best -1
    : ~ i best_score 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [ImpCol] cols k ) {
            T c → {
                : i strength ( __it_role_strength ( string_data . c norm ) role )
                : ~ b fits F
                ? == role ROLE_YEAR { = fits ( __it_mostly . c n_year . c filled ) } {}
                ? == role ROLE_MONTH { = fits ( __it_mostly . c n_month . c filled ) } {}
                ? == role ROLE_DAY { = fits ( __it_mostly . c n_day . c filled ) } {}
                ? == role ROLE_HOUR { = fits ( __it_mostly . c n_hour . c filled ) } {}
                ? | == role ROLE_MINUTE == role ROLE_SECOND { = fits ( __it_mostly . c n_minsec . c filled ) } {}
                ? == role ROLE_CLOCK { = fits ( __it_mostly . c n_clock . c filled ) } {}
                ? == role ROLE_DATE { = fits ( __it_mostly . c n_date . c filled ) } {}
                ? == role ROLE_STAMP {
                    = fits ( __it_mostly . c n_dt . c filled )
                    // A bare number column is a Unix clock only when it is
                    // called one: a counter in the billions is not a date.
                    ? & ! fits ( __it_mostly . c n_unix . c filled ) { = fits > strength 0 } {}
                } {}
                // Names decide the part roles (a column of 1..12 could be
                // anything); values decide the stamp roles, names rank.
                : b named_role | | == role ROLE_STAMP == role ROLE_CLOCK == role ROLE_DATE
                : i score ? fits ? named_role + 1 strength strength 0
                ? & > score 0 > score best_score { = best k = best_score score } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ best
}

@ __it_name_at ( Vec ImpCol ) cols i k → s {
    ?? ( vec_get [ImpCol] cols k ) { T c → { ^ ( string_data . c cname ) } F _ → {} }
    ^ ``
}

@ __it_strength_at ( Vec ImpCol ) cols i k i role → i {
    ?? ( vec_get [ImpCol] cols k ) { T c → { ^ ( __it_role_strength ( string_data . c norm ) role ) } F _ → {} }
    ^ 0
}

// The plan: `{ mode: column|parts|none, column?, parts?: {year, month,
// day, hour, minute, second, date, clock}, confidence: high|guess|none,
// reason }`. Every named column exists and fits its role.
@ import_time_propose ( Vec ImpCol ) cols → Json {
    : Json plan ( json_obj_new )

    // One column that is a whole date and time.
    : i st ( __it_best cols ROLE_STAMP )
    ? >= st 0 {
        ( json_obj_set plan `mode` ( json_str_lit `column` ) )
        ( json_obj_set plan `column` ( json_str_lit ( __it_name_at cols st ) ) )
        : b strong >= ( __it_strength_at cols st ROLE_STAMP ) 1
        ( json_obj_set plan `confidence` ( json_str_lit ? strong `high` `guess` ) )
        ( json_obj_set plan `reason` ( json_str_lit ? strong `a column named for time whose values read as timestamps` `a column whose values read as timestamps, though its name does not say so` ) )
        ^ plan
    } {}

    // A date column, with or without a clock column beside it.
    : i dt ( __it_best cols ROLE_DATE )
    : i cl ( __it_best cols ROLE_CLOCK )
    ? >= dt 0 {
        : Json parts ( json_obj_new )
        ( json_obj_set parts `date` ( json_str_lit ( __it_name_at cols dt ) ) )
        ? >= cl 0 { ( json_obj_set parts `clock` ( json_str_lit ( __it_name_at cols cl ) ) ) } {}
        ( json_obj_set plan `mode` ( json_str_lit `parts` ) )
        ( json_obj_set plan `parts` parts )
        ( json_obj_set plan `confidence` ( json_str_lit `high` ) )
        ( json_obj_set plan `reason` ( json_str_lit ? >= cl 0 `a date column and a time-of-day column` `a date column (midnight; no time of day found)` ) )
        ^ plan
    } {}

    // Year, month and day columns, then whatever finer parts exist.
    : i y ( __it_best cols ROLE_YEAR )
    : i mo ( __it_best cols ROLE_MONTH )
    : i d ( __it_best cols ROLE_DAY )
    ? & & >= y 0 >= mo 0 >= d 0 {
        : Json parts ( json_obj_new )
        ( json_obj_set parts `year` ( json_str_lit ( __it_name_at cols y ) ) )
        ( json_obj_set parts `month` ( json_str_lit ( __it_name_at cols mo ) ) )
        ( json_obj_set parts `day` ( json_str_lit ( __it_name_at cols d ) ) )
        : ~ i weakest ( __it_strength_at cols y ROLE_YEAR )
        : i sm ( __it_strength_at cols mo ROLE_MONTH )
        : i sd ( __it_strength_at cols d ROLE_DAY )
        ? < sm weakest { = weakest sm } {}
        ? < sd weakest { = weakest sd } {}
        ? >= cl 0 {
            ( json_obj_set parts `clock` ( json_str_lit ( __it_name_at cols cl ) ) )
        } {
            : i h ( __it_best cols ROLE_HOUR )
            ? >= h 0 {
                ( json_obj_set parts `hour` ( json_str_lit ( __it_name_at cols h ) ) )
                : i sh ( __it_strength_at cols h ROLE_HOUR )
                ? < sh weakest { = weakest sh } {}
                : i mi ( __it_best cols ROLE_MINUTE )
                ? & >= mi 0 != mi h {
                    ( json_obj_set parts `minute` ( json_str_lit ( __it_name_at cols mi ) ) )
                    : i smi ( __it_strength_at cols mi ROLE_MINUTE )
                    ? < smi weakest { = weakest smi } {}
                    : i se ( __it_best cols ROLE_SECOND )
                    ? & & >= se 0 != se mi != se h {
                        ( json_obj_set parts `second` ( json_str_lit ( __it_name_at cols se ) ) )
                        : i sse ( __it_strength_at cols se ROLE_SECOND )
                        ? < sse weakest { = weakest sse } {}
                    } {}
                } {}
            } {}
        }
        ( json_obj_set plan `mode` ( json_str_lit `parts` ) )
        ( json_obj_set plan `parts` parts )
        ( json_obj_set plan `confidence` ( json_str_lit ? >= weakest 2 `high` `guess` ) )
        ( json_obj_set plan `reason` ( json_str_lit ? >= weakest 2 `year, month and day columns` `columns whose short names may mean year, month, day, hour, minute or second — or something else` ) )
        ^ plan
    } {}

    ( json_obj_set plan `mode` ( json_str_lit `none` ) )
    ( json_obj_set plan `confidence` ( json_str_lit `none` ) )
    ( json_obj_set plan `reason` ( json_str_lit `no column reads as a timestamp and no year/month/day columns were found` ) )
    ^ plan
}

// Columns that could serve each role, for a picker: `{ role: [names] }`.
@ __it_hints ( Vec ImpCol ) cols → Json {
    : Json out ( json_obj_new )
    : i n ( vec_len [ImpCol] cols )
    : ~ i role 0
    ~ <= role ROLE_CLOCK {
        : Json arr ( json_arr_new )
        : ~ i k 0
        ~ < k n {
            ?? ( vec_get [ImpCol] cols k ) {
                T c → {
                    : ~ b ok F
                    ? == role ROLE_STAMP { = ok | ( __it_mostly . c n_dt . c filled ) & ( __it_mostly . c n_unix . c filled ) > ( __it_role_strength ( string_data . c norm ) ROLE_STAMP ) 0 } {}
                    ? == role ROLE_DATE { = ok ( __it_mostly . c n_date . c filled ) } {}
                    ? == role ROLE_CLOCK { = ok ( __it_mostly . c n_clock . c filled ) } {}
                    ? == role ROLE_YEAR { = ok & ( __it_mostly . c n_year . c filled ) > ( __it_role_strength ( string_data . c norm ) role ) 0 } {}
                    ? == role ROLE_MONTH { = ok & ( __it_mostly . c n_month . c filled ) > ( __it_role_strength ( string_data . c norm ) role ) 0 } {}
                    ? == role ROLE_DAY { = ok & ( __it_mostly . c n_day . c filled ) > ( __it_role_strength ( string_data . c norm ) role ) 0 } {}
                    ? == role ROLE_HOUR { = ok & ( __it_mostly . c n_hour . c filled ) > ( __it_role_strength ( string_data . c norm ) role ) 0 } {}
                    ? | == role ROLE_MINUTE == role ROLE_SECOND { = ok & ( __it_mostly . c n_minsec . c filled ) > ( __it_role_strength ( string_data . c norm ) role ) 0 } {}
                    ? ok { ( json_arr_push arr ( json_str_lit ( string_data . c cname ) ) ) } {}
                }
                F _ → {}
            }
            = k + k 1
        }
        : ~ s rname `stamp`
        ? == role ROLE_YEAR { = rname `year` } {}
        ? == role ROLE_MONTH { = rname `month` } {}
        ? == role ROLE_DAY { = rname `day` } {}
        ? == role ROLE_HOUR { = rname `hour` } {}
        ? == role ROLE_MINUTE { = rname `minute` } {}
        ? == role ROLE_SECOND { = rname `second` } {}
        ? == role ROLE_DATE { = rname `date` } {}
        ? == role ROLE_CLOCK { = rname `clock` } {}
        ( json_obj_set out rname arr )
        = role + role 1
    }
    ^ out
}

// ── Applying a plan ───────────────────────────────────────────────────

// A numeric cell as an integer, or -1: a year written "2026" in a CSV
// arrives as a number, in JSON it may be a string.
@ __it_int_of Json v → i {
    ? ( json_is_num v ) { ?? ( json_num_as_i v ) { T x → { ^ x } F _ → { ^ -1 } } } {}
    ? ( json_is_str v ) {
        : String t ( string_from ( json_str_data v ) )
        : !i ParseErr r ( string_to_int t )
        ( string_free t )
        ?? r { T x → { ^ x } F _ → { ^ -1 } }
    } {}
    ^ -1
}

@ __it_part_int Json row Json parts s role → i {
    ?? ( json_obj_get parts role ) {
        T pn → {
            ? ( json_is_str pn ) {
                ?? ( json_obj_get row ( json_str_data pn ) ) { T v → { ^ ( __it_int_of v ) } F _ → { ^ -1 } }
            } { ^ -1 }
        }
        F _ → { ^ -1 }
    }
    ^ -1
}

@ __it_part_stamp Json row Json parts s role → ImpStamp {
    ?? ( json_obj_get parts role ) {
        T pn → {
            ? ( json_is_str pn ) {
                ?? ( json_obj_get row ( json_str_data pn ) ) { T v → { ^ ( imp_stamp_of v ) } F _ → { ^ ( __it_none ) } }
            } { ^ ( __it_none ) }
        }
        F _ → { ^ ( __it_none ) }
    }
    ^ ( __it_none )
}

// The Unix seconds one row's plan yields, or -1.
@ __it_row_secs Json row Json plan i tz → i {
    : s mode ?? ( json_obj_get plan `mode` ) { T m → ( json_as_str m ) F _ → `none` }
    ? == ( nurl_str_eq mode `column` ) 1 {
        ?? ( json_obj_get plan `column` ) {
            T cn → {
                ?? ( json_obj_get row ( json_as_str cn ) ) {
                    T v → {
                        : ImpStamp st ( imp_stamp_of v )
                        ? | == . st kind STAMP_NONE == . st kind STAMP_CLOCK { ^ -1 } {}
                        ^ ( __it_finish . st secs . st zoned tz )
                    }
                    F _ → { ^ -1 }
                }
            }
            F _ → { ^ -1 }
        }
    } {}
    ? == ( nurl_str_eq mode `parts` ) 1 {
        ?? ( json_obj_get plan `parts` ) {
            T parts → {
                : ~ i naive -1
                : ~ b zoned F
                ? ( json_obj_has parts `date` ) {
                    : ImpStamp ds ( __it_part_stamp row parts `date` )
                    ? | == . ds kind STAMP_DATE == . ds kind STAMP_DATETIME { = naive . ds secs = zoned . ds zoned } {}
                } {
                    : i y ( __it_part_int row parts `year` )
                    : i mo ( __it_part_int row parts `month` )
                    : i d ( __it_part_int row parts `day` )
                    : !i ParseErr mk ( time_make y mo d 0 0 0 )
                    ?? mk { T x → { = naive x } F _ → {} }
                }
                ? < naive 0 { ^ -1 } {}
                : ~ i tod 0
                ? ( json_obj_has parts `clock` ) {
                    : ImpStamp cs ( __it_part_stamp row parts `clock` )
                    ? == . cs kind STAMP_CLOCK { = tod . cs secs } { ^ -1 }
                } {
                    : i h ( __it_part_int row parts `hour` )
                    : i mi ( __it_part_int row parts `minute` )
                    : i se ( __it_part_int row parts `second` )
                    ? ( json_obj_has parts `hour` ) { ? | < h 0 > h 23 { ^ -1 } { = tod * h 3600 } } {}
                    ? ( json_obj_has parts `minute` ) { ? | < mi 0 > mi 59 { ^ -1 } { = tod + tod * mi 60 } } {}
                    ? ( json_obj_has parts `second` ) { ? | < se 0 > se 60 { ^ -1 } { = tod + tod se } } {}
                }
                ^ ( __it_finish + naive tod zoned tz )
            }
            F _ → { ^ -1 }
        }
    } {}
    ^ -1
}

// The columns a plan consumes, so they leave the record.
@ __it_plan_columns Json plan → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( json_obj_get plan `column` ) {
        T cn → { ? ( json_is_str cn ) { ( vec_push [String] out ( string_from ( json_str_data cn ) ) ) } {} }
        F _ → {}
    }
    ?? ( json_obj_get plan `parts` ) {
        T parts → {
            : ( Vec String ) roles ( json_obj_keys parts )
            : i n ( vec_len [String] roles )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] roles k ) {
                    T r → {
                        ?? ( json_obj_get parts ( string_data r ) ) {
                            T cn → { ? ( json_is_str cn ) { ( vec_push [String] out ( string_from ( json_str_data cn ) ) ) } {} }
                            F _ → {}
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] roles \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ^ out
}

@ __it_in_list ( Vec String ) l s name → b {
    : i n ( vec_len [String] l )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] l k ) {
            T x → { ? == ( nurl_str_eq ( string_data x ) name ) 1 { ^ T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// A row without the consumed columns, with `timestamp` and (when asked)
// `time` set.
@ __it_restamp Json row ( Vec String ) drop i secs b calendar i tz → Json {
    : Json out ( json_obj_new )
    : ( Vec String ) keys ( json_obj_keys row )
    : i n ( vec_len [String] keys )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] keys k ) {
            T key → {
                : s kn ( string_data key )
                ? | | ( __it_in_list drop kn ) == ( nurl_str_eq kn `timestamp` ) 1 & calendar == ( nurl_str_eq kn `time` ) 1 {} {
                    ?? ( json_obj_get row kn ) { T v → { ( json_obj_set out kn ( json_clone v ) ) } F _ → {} }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ( json_obj_set out `timestamp` ( json_int secs ) )
    ? calendar {
        : i off ( __it_off_at secs tz )
        : Time lt ( time_from_unix + secs off )
        : String iso ( time_format_offset lt off )
        ( json_obj_set out `time` ( json_str_lit ( string_data iso ) ) )
        ( string_free iso )
    } {}
    ^ out
}

: ImpTimeResult {
    i stamped
    i failed  // rows the plan could not read a time from — dropped
    String first_fail  // what the first of them looked like
}

@ imp_time_result_free ImpTimeResult r → v { ( string_free . r first_fail ) }

// Rewrite `rows` in place under `plan`. With mode `none` nothing changes.
// A row whose time cannot be read is removed: a history point with no
// place in history is not a point this model can hold.
@ import_time_apply ( Vec Json ) rows Json plan b calendar i tz → ImpTimeResult {
    : s mode ?? ( json_obj_get plan `mode` ) { T m → ( json_as_str m ) F _ → `none` }
    ? | == ( nurl_str_eq mode `column` ) 1 == ( nurl_str_eq mode `parts` ) 1 {} {
        ^ @ ImpTimeResult { 0 0 ( string_new ) }
    }
    : ( Vec String ) drop ( __it_plan_columns plan )
    : i n ( vec_len [Json] rows )
    : ~ i stamped 0
    : ~ i failed 0
    : ~ String first ( string_new )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [Json] rows k ) {
            T row → {
                : i secs ( __it_row_secs row plan tz )
                ? >= secs 0 {
                    : Json nr ( __it_restamp row drop secs calendar tz )
                    : b _s ( vec_set [Json] rows k nr )
                    ( json_free row )
                    = stamped + stamped 1
                } {
                    = failed + failed 1
                    ? == ( string_len first ) 0 {
                        ( string_free first )
                        = first ( string_from `row ` )
                        ( string_push_int first + k 1 )
                        ( string_push_str first `: no time could be read from ` )
                        : ~ i q 0
                        : i nd ( vec_len [String] drop )
                        ~ < q nd {
                            ?? ( vec_get [String] drop q ) {
                                T cn → {
                                    ? > q 0 { ( string_push_str first `, ` ) } {}
                                    ( string_push_str first ( string_data cn ) )
                                    ( string_push_str first `=` )
                                    ?? ( json_obj_get row ( string_data cn ) ) {
                                        T v → {
                                            : String sv ( json_stringify v )
                                            ( string_push_str first ( string_data sv ) )
                                            ( string_free sv )
                                        }
                                        F _ → { ( string_push_str first `(missing)` ) }
                                    }
                                }
                                F _ → {}
                            }
                            = q + q 1
                        }
                    } {}
                    // Drop it: swap the slot to an empty marker, compact below.
                    : b _s ( vec_set [Json] rows k ( json_obj_new ) )
                    ( json_free row )
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] drop \ String x → v { ( string_free x ) } )
    ? > failed 0 {
        // Compact: a failed row became an empty object; keep the rest.
        : ( Vec Json ) kept ( vec_with_cap [Json] stamped )
        = k 0
        ~ < k n {
            ?? ( vec_get [Json] rows k ) {
                T row → {
                    ? ( json_obj_has row `timestamp` ) { ( vec_push [Json] kept row ) } { ( json_free row ) }
                }
                F _ → {}
            }
            = k + k 1
        }
        ( vec_clear [Json] rows )
        ( vec_extend [Json] rows kept )
        ( vec_free [Json] kept )
    } {}
    ^ @ ImpTimeResult { stamped failed first }
}

// ── Resolving what the caller asked for ───────────────────────────────

// Turn a request (`{ mode: auto|none|column|parts, column?, parts? }`)
// into a concrete plan against these columns. `auto` becomes the
// proposal; a named column that does not exist is an error (non-empty
// `err`).
: ImpPlan {
    Json plan
    String err
}

@ imp_plan_free ImpPlan p → v {
    ( json_free . p plan )
    ( string_free . p err )
}

@ __it_check_col ( Vec ImpCol ) cols s name String err → v {
    ? >= ( __it_col_find cols name ) 0 {} {
        ? == ( string_len err ) 0 {
            ( string_push_str err `the file has no column named "` )
            ( string_push_str err name )
            ( string_push_str err `"` )
        } {}
    }
}

@ import_time_plan ( Vec ImpCol ) cols Json spec → ImpPlan {
    : s mode ?? ( json_obj_get spec `mode` ) { T m → ? ( json_is_str m ) ( json_str_data m ) `auto` F _ → `auto` }
    ? == ( nurl_str_eq mode `auto` ) 1 { ^ @ ImpPlan { ( import_time_propose cols ) ( string_new ) } } {}
    ? == ( nurl_str_eq mode `none` ) 1 {
        : Json p ( json_obj_new )
        ( json_obj_set p `mode` ( json_str_lit `none` ) )
        ^ @ ImpPlan { p ( string_new ) }
    } {}
    : ~ String err ( string_new )
    : Json p ( json_obj_new )
    ? == ( nurl_str_eq mode `column` ) 1 {
        ( json_obj_set p `mode` ( json_str_lit `column` ) )
        ?? ( json_obj_get spec `column` ) {
            T cn → {
                ? ( json_is_str cn ) {
                    ( __it_check_col cols ( json_str_data cn ) err )
                    ( json_obj_set p `column` ( json_clone cn ) )
                } { ( string_push_str err `"column" must name a column` ) }
            }
            F _ → { ( string_push_str err `mode "column" needs a "column"` ) }
        }
        ^ @ ImpPlan { p err }
    } {}
    ? == ( nurl_str_eq mode `parts` ) 1 {
        ( json_obj_set p `mode` ( json_str_lit `parts` ) )
        ?? ( json_obj_get spec `parts` ) {
            T parts → {
                ? ( json_is_obj parts ) {
                    : Json cp ( json_obj_new )
                    : ( Vec String ) roles ( json_obj_keys parts )
                    : i n ( vec_len [String] roles )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [String] roles k ) {
                            T r → {
                                : s rn ( string_data r )
                                ? ( __it_in rn `|year|month|day|hour|minute|second|date|clock|` ) {
                                    ?? ( json_obj_get parts rn ) {
                                        T cn → {
                                            // An empty name means "not this part".
                                            ? & ( json_is_str cn ) > ( nurl_str_len ( json_str_data cn ) ) 0 {
                                                ( __it_check_col cols ( json_str_data cn ) err )
                                                ( json_obj_set cp rn ( json_clone cn ) )
                                            } {}
                                        }
                                        F _ → {}
                                    }
                                } {}
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                    ( vec_free_with [String] roles \ String x → v { ( string_free x ) } )
                    : b has_date | ( json_obj_has cp `date` ) & & ( json_obj_has cp `year` ) ( json_obj_has cp `month` ) ( json_obj_has cp `day` )
                    ? | has_date > ( string_len err ) 0 {} {
                        ( string_push_str err `parts need a "date" column, or "year", "month" and "day"` )
                    }
                    ( json_obj_set p `parts` cp )
                } { ( string_push_str err `"parts" must map roles to column names` ) }
            }
            F _ → { ( string_push_str err `mode "parts" needs a "parts" object` ) }
        }
        ^ @ ImpPlan { p err }
    } {}
    ( string_push_str err `time mode must be "auto", "none", "column" or "parts"` )
    ^ @ ImpPlan { p err }
}

// ── The description a caller sees ─────────────────────────────────────

// `{ columns: [{ name, kind, filled, sample }], time: <plan + sample>,
// hints: { role: [names] } }`. `time.sample` is the first row's time
// under the plan, as ISO in the zone, so a person can check the guess
// against the file with their own eyes.
@ import_inspect ( Vec Json ) rows Json spec i tz → Json {
    : ( Vec ImpCol ) cols ( __it_describe rows )
    : Json out ( json_obj_new )

    : Json carr ( json_arr_new )
    : i nc ( vec_len [ImpCol] cols )
    : ~ i k 0
    ~ < k nc {
        ?? ( vec_get [ImpCol] cols k ) {
            T c → {
                : Json co ( json_obj_new )
                ( json_obj_set co `name` ( json_str_lit ( string_data . c cname ) ) )
                ( json_obj_set co `kind` ( json_str_lit ( __it_col_kind c ) ) )
                ( json_obj_set co `filled` ( json_int . c filled ) )
                ( json_obj_set co `sample` ( json_str_lit ( string_data . c sample ) ) )
                ( json_arr_push carr co )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( json_obj_set out `columns` carr )
    ( json_obj_set out `rows_described` ( json_int ? < ( vec_len [Json] rows ) ANOM_INSPECT_ROWS ( vec_len [Json] rows ) ANOM_INSPECT_ROWS ) )

    : ImpPlan ip ( import_time_plan cols spec )
    : Json plan ( json_clone . ip plan )
    ? > ( string_len . ip err ) 0 { ( json_obj_set plan `error` ( json_str_lit ( string_data . ip err ) ) ) } {}
    ? > ( vec_len [Json] rows ) 0 {
        ?? ( vec_get [Json] rows 0 ) {
            T r0 → {
                : i secs ( __it_row_secs r0 plan tz )
                ? >= secs 0 {
                    : i off ( __it_off_at secs tz )
                    : String iso ( time_format_offset ( time_from_unix + secs off ) off )
                    ( json_obj_set plan `sample` ( json_str_lit ( string_data iso ) ) )
                    ( json_obj_set plan `sample_unix` ( json_int secs ) )
                    ( string_free iso )
                } {}
            }
            F _ → {}
        }
    } {}
    ( json_obj_set out `time` plan )
    ( json_obj_set out `hints` ( __it_hints cols ) )
    ( imp_plan_free ip )
    ( vec_free_with [ImpCol] cols \ ImpCol c → v { ( __it_col_free c ) } )
    ^ out
}
