// stdlib/std/time.nu — wall-clock + monotonic time, sleep, calendar
//
//   ( now_ms )            → i      ms since Unix epoch (CLOCK_REALTIME)
//   ( now_seconds )       → i      seconds since Unix epoch
//   ( monotonic_ns )      → i      monotonic nanoseconds (NOT epoch-relative,
//                                  use only for measuring elapsed time)
//   ( sleep_ms ms )       → v      sleep for `ms` milliseconds
//                                  (0 / negative ⇒ no-op; signal-safe retry)
//   ( elapsed_ms_since t0 ) → i    convenience: monotonic_ns − t0 → ms
//
// Calendar (UTC):
//
//   ( time_from_unix i secs )      → Time         civil_from_days alg.
//   ( time_to_unix Time t )        → i            inverse, days_from_civil
//   ( time_now )                   → Time         convenience for now_seconds
//   ( time_format_iso  Time t )    → String       "2026-05-06T17:30:45Z"
//   ( time_format_http Time t )    → String       "Wed, 06 May 2026 17:30:45 GMT"
//   ( time_parse_iso s txt )       → ! Time ParseErr
//
// Typical benchmark pattern:
//   : i t0 ( monotonic_ns )
//   ( do_work )
//   : i ms ( elapsed_ms_since t0 )
//   ( nurl_print ( nurl_str_int ms ) )
//
// Caveats:
//   - `now_ms` is wall-clock; subject to NTP slew. Use `monotonic_ns`
//     for elapsed-time measurements.
//   - All timestamps are i64; ns-precision overflows i64 in ~292 years.
//   - Calendar arithmetic is UTC only. No timezone or DST handling —
//     callers that need local time should keep the offset themselves.

$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

@ now_ms → i {
    ^ ( nurl_now_ms )
}

@ now_seconds → i {
    ^ ( nurl_now_seconds )
}

@ monotonic_ns → i {
    ^ ( nurl_monotonic_ns )
}

@ sleep_ms i ms → v {
    ( nurl_sleep_ms ms )
}

@ elapsed_ms_since i t0 → i {
    : i now ( nurl_monotonic_ns )
    ^ / - now t0 1000000
}

// ── Calendar (UTC) ──────────────────────────────────────────────────
//
// Howard Hinnant's `civil_from_days` / `days_from_civil` algorithms
// (proleptic Gregorian, public domain — see
// http://howardhinnant.github.io/date_algorithms.html). Constant-time,
// branch-free, correct for the full range of i64 day counts.

: Time {
    i year  // proleptic Gregorian year (full, e.g. 2026 not 26)
    i month  // 1..12
    i day  // 1..31
    i hour  // 0..23
    i min  // 0..59
    i sec  // 0..59 (no leap seconds — POSIX time convention)
    i ns  // 0..999_999_999 (sub-second resolution; 0 in time_now)
    i wday  // 0=Sun..6=Sat (Hinnant's weekday_from_days convention)
}

// Floor division: truncates toward negative infinity (NURL's `/` is
// the C-style truncate-toward-zero operator). Civil-time arithmetic
// needs floor semantics so dates before 1970 round correctly.
@ __i_floor_div i a i b → i {
    : i q / a b
    : i r - a * q b
    ? != r 0 {
        ? & < r 0 > b 0 { ^ - q 1 } {}
        ? & > r 0 < b 0 { ^ - q 1 } {}
    } {}
    ^ q
}

@ __i_mod i a i b → i {
    : i r - a * ( __i_floor_div a b ) b
    ^ r
}

// civil_from_days: convert days-since-1970-01-01 → (year, month, day, wday).
@ __civil_from_days i z → Time {
    : i zz + z 719468
    : i era ( __i_floor_div zz 146097 )
    : i doe - zz * era 146097
    // yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    : i yoe / - + - doe / doe 1460 / doe 36524 / doe 146096 365
    : ~ i y + yoe * era 400
    // doy = doe - (yoe*365 + yoe/4 - yoe/100)
    : i doy - doe - + * 365 yoe / yoe 4 / yoe 100
    // mp = (5*doy + 2) / 153
    : i mp / + * 5 doy 2 153
    // d = doy - (153*mp + 2)/5 + 1
    : i d + - doy / + * 153 mp 2 5 1
    // m = mp < 10 ? mp+3 : mp-9
    : i m ? < mp 10 + mp 3 - mp 9
    ? <= m 2 { = y + y 1 } {}
    // weekday_from_days uses the ORIGINAL 1970-relative z, not zz.
    : i wday ( __i_mod + z 4 7 )
    ^ @ Time { y m d 0 0 0 0 wday }
}

// days_from_civil: inverse — (year, month, day) → days since 1970-01-01.
@ __days_from_civil i y i m i d → i {
    : i y2 ? <= m 2 - y 1 y
    : i era ( __i_floor_div y2 400 )
    : i yoe - y2 * era 400
    : i doy - + / + * 153 + m ? > m 2 -3 9 2 5 d 1
    : i doe + - + * yoe 365 / yoe 4 / yoe 100 doy
    ^ - + * era 146097 doe 719468
}

@ time_from_unix i secs → Time {
    : i day_secs ( __i_floor_div secs 86400 )
    : i sod ( __i_mod secs 86400 )
    : Time t ( __civil_from_days day_secs )
    : i hh / sod 3600
    : i mm / - sod * hh 3600 60
    : i ss - sod + * hh 3600 * mm 60
    ^ @ Time { . t year . t month . t day hh mm ss 0 . t wday }
}

@ time_to_unix Time t → i {
    : i days ( __days_from_civil . t year . t month . t day )
    ^ + + + * days 86400 * . t hour 3600 * . t min 60 . t sec
}

@ time_now → Time {
    ^ ( time_from_unix ( now_seconds ) )
}

// ── Formatting ───────────────────────────────────────────────────────

@ __push_2digit String out i n → v {
    ( string_push_char out + 48 / n 10 )
    ( string_push_char out + 48 ( __i_mod n 10 ) )
}

@ __push_4digit String out i n → v {
    : i a / n 1000
    : i b / ( __i_mod n 1000 ) 100
    : i c / ( __i_mod n 100 ) 10
    : i d ( __i_mod n 10 )
    ( string_push_char out + 48 a )
    ( string_push_char out + 48 b )
    ( string_push_char out + 48 c )
    ( string_push_char out + 48 d )
}

@ time_format_iso Time t → String {
    : String out ( string_with_cap 24 )
    ( __push_4digit out . t year )
    ( string_push_char out 45 )
    ( __push_2digit out . t month )
    ( string_push_char out 45 )
    ( __push_2digit out . t day )
    ( string_push_char out 84 )
    ( __push_2digit out . t hour )
    ( string_push_char out 58 )
    ( __push_2digit out . t min )
    ( string_push_char out 58 )
    ( __push_2digit out . t sec )
    ( string_push_char out 90 )
    ^ out
}

@ __wday_name i w → s {
    ? == w 0 { ^ `Sun` } {}
    ? == w 1 { ^ `Mon` } {}
    ? == w 2 { ^ `Tue` } {}
    ? == w 3 { ^ `Wed` } {}
    ? == w 4 { ^ `Thu` } {}
    ? == w 5 { ^ `Fri` } {}
    ? == w 6 { ^ `Sat` } {}
    ^ `???`
}

@ __month_name i m → s {
    ? == m 1 { ^ `Jan` } {}
    ? == m 2 { ^ `Feb` } {}
    ? == m 3 { ^ `Mar` } {}
    ? == m 4 { ^ `Apr` } {}
    ? == m 5 { ^ `May` } {}
    ? == m 6 { ^ `Jun` } {}
    ? == m 7 { ^ `Jul` } {}
    ? == m 8 { ^ `Aug` } {}
    ? == m 9 { ^ `Sep` } {}
    ? == m 10 { ^ `Oct` } {}
    ? == m 11 { ^ `Nov` } {}
    ? == m 12 { ^ `Dec` } {}
    ^ `???`
}

// RFC 7231 §7.1.1.1 — IMF-fixdate format used by HTTP `Date:` and
// `Expires:` headers: "Wed, 06 May 2026 17:30:45 GMT".
@ time_format_http Time t → String {
    : String out ( string_with_cap 32 )
    ( string_push_str out ( __wday_name . t wday ) )
    ( string_push_str out `, ` )
    ( __push_2digit out . t day )
    ( string_push_char out 32 )
    ( string_push_str out ( __month_name . t month ) )
    ( string_push_char out 32 )
    ( __push_4digit out . t year )
    ( string_push_char out 32 )
    ( __push_2digit out . t hour )
    ( string_push_char out 58 )
    ( __push_2digit out . t min )
    ( string_push_char out 58 )
    ( __push_2digit out . t sec )
    ( string_push_str out ` GMT` )
    ^ out
}

// ── Parsing ───────────────────────────────────────────────────────────
//
// Strict ISO 8601 reader: "YYYY-MM-DDTHH:MM:SS[Z|+HH:MM|-HH:MM]".
// 'T' separator may be lowercase. Trailing offset is folded to UTC.
// Sub-second decimals (".sss" or ".ssssss") are accepted but ignored
// for now — a future revision can populate `Time.ns`.

@ __char_at_eq s p i idx i target → b {
    : i n ( nurl_str_len p )
    ? < idx 0 { ^ F } {}
    ? >= idx n { ^ F } {}
    ^ == ( nurl_str_get p idx ) target
}

@ __take_ndigits s p i start i count i max_idx → i {
    ? > + start count max_idx { ^ -1 } {}
    : ~ i acc 0
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k count {
        : i c ( nurl_str_get p + start k )
        ? & >= c 48 <= c 57 {
            = acc + * acc 10 - c 48
        } { = ok F }
        = k + k 1
    }
    ? ! ok { ^ -1 } {}
    ^ acc
}

@ time_parse_iso s p → !Time ParseErr {
    : i n ( nurl_str_len p )
    ? < n 19 { ^ @ !Time ParseErr { F @ ParseErr { Empty } } } {}

    : i y ( __take_ndigits p 0 4 n )
    ? < y 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 4 45 ) { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    : i mo ( __take_ndigits p 5 2 n )
    ? < mo 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 7 45 ) { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    : i d ( __take_ndigits p 8 2 n )
    ? < d 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}

    : i sep ( nurl_str_get p 10 )
    ? & != sep 84 != sep 116 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}

    : i hh ( __take_ndigits p 11 2 n )
    ? < hh 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 13 58 ) { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    : i mm ( __take_ndigits p 14 2 n )
    ? < mm 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 16 58 ) { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
    : i ss ( __take_ndigits p 17 2 n )
    ? < ss 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}

    : ~ i k 19
    // Optional fractional seconds (ignored, just consume).
    ? & < k n == ( nurl_str_get p k ) 46 {
        = k + k 1
        ~ & < k n & >= ( nurl_str_get p k ) 48 <= ( nurl_str_get p k ) 57 {
            = k + k 1
        }
    } {}

    : ~ i offset_min 0
    ? < k n {
        : i tc ( nurl_str_get p k )
        ? | == tc 90 == tc 122 {
            = k + k 1
        } {
            ? | == tc 43 == tc 45 {
                : i sign ? == tc 45 -1 1
                = k + k 1
                : i oh ( __take_ndigits p k 2 n )
                ? < oh 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
                = k + k 2
                ? & < k n == ( nurl_str_get p k ) 58 { = k + k 1 } {}
                : i om ( __take_ndigits p k 2 n )
                ? < om 0 { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } } {}
                = k + k 2
                = offset_min * sign + * oh 60 om
            } { ^ @ !Time ParseErr { F @ ParseErr { BadFormat } } }
        }
    } {}
    ? != k n { ^ @ !Time ParseErr { F @ ParseErr { TrailingGarbage } } } {}

    : i unix_local ( time_to_unix @ Time { y mo d hh mm ss 0 0 } )
    : i unix_utc - unix_local * offset_min 60
    ^ @ !Time ParseErr { T ( time_from_unix unix_utc ) }
}
