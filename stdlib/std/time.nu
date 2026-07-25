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
//   ( time_make Y Mo D H Mi S )    → ! i ParseErr   validated → Unix secs
//   ( is_leap_year i y )           → b
//   ( days_in_month i y i m )      → i             leap-aware month length
//   ( time_yday Time t )           → i             day of year, 1..365/366
//   ( time_cmp a b )               → i             -1 / 0 / 1
//   ( time_eq / time_before / time_after a b ) → b
//   ( time_add_seconds Time t i n )  → Time         (negative subtracts)
//   ( time_add_days    Time t i n )  → Time         rolls month/year over
//   ( time_diff_seconds a b )      → i             signed a − b
//   ( time_format Time t s fmt )   → String        strftime subset
//   ( time_format_iso  Time t )    → String        "2026-05-06T17:30:45Z"
//   ( time_format_http Time t )    → String        "Wed, 06 May 2026 17:30:45 GMT"
//   ( time_parse_iso s txt )       → ! i ParseErr   parsed → Unix secs
//
// time_make / time_parse_iso yield the Unix timestamp (an `i`), not a
// `Time` — a narrow `i` payload is immune to the wide-`! T E`-payload
// truncation bug. Convert with `time_from_unix` when you need fields.
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
//   - The calendar core (above) is UTC only. Local-time conversion and
//     DST live in §12b below (tz_parse / time_from_unix_tz / …), driven
//     by a POSIX TZ string; there is no IANA tzdata region lookup.

$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/posix.nu`  // posix_const + nurl_errno_get + nurl_native_sizeof
// sleep_ms is fiber-aware via the runtime — parks on the reactor's
// timer wheel when invoked from a fiber, blocks via nanosleep when
// invoked from a plain OS thread.
$ `stdlib/std/async_ffi.nu`

// ── §12 Time — pure-NURL libc FFI ────────────────────────────────────
//
// PURIFY (2026-05-24): the four runtime helpers (`nurl_now_ms` /
// `_now_seconds` / `_monotonic_ns` / `_sleep_ms`) are gone — every
// supported target reaches `clock_gettime(2)` / `nanosleep(2)` through
// libc directly. Linux + macOS expose them in their primary libc;
// MinGW-w64 routes through winpthreads (we already link `-lpthread` on
// Win32 from Phase 6); wasi-libc wraps the WASI snapshot-1 syscalls.
//
// Buffer layout: `struct timespec` is `{ time_t tv_sec; long tv_nsec; }`.
// On every supported 64-bit POSIX target it is 16 bytes (8 + 8); on
// MinGW Win32 it is 12 bytes packed (`long` is 32 bits on LLP64) but
// the struct's natural alignment is 8, so its sizeof rounds to 16.
// Allocating 16 bytes via `nurl_zalloc` covers every layout: the
// trailing pad on Win32/WASI stays zeroed so `nurl_peek` of slot 1
// returns the 32-bit `tv_nsec` extended with zeros — the correct value.

& `c` @ clock_gettime i32 clock_id *u tp → i32

& `c` @ nanosleep *u req *u rem → i32

@ now_ms → i {
    : s ts ( nurl_zalloc 16 )
    : i32 rc ( clock_gettime # i32 ( posix_const `CLOCK_REALTIME` ) # *u ts )
    ? != rc 0 { ( nurl_free ts ) ^ 0 } {}
    : i secs ( nurl_peek ts 0 )
    : i nsec ( nurl_peek ts 1 )
    ( nurl_free ts )
    ^ + * secs 1000 / nsec 1000000
}

@ now_seconds → i {
    : s ts ( nurl_zalloc 16 )
    : i32 rc ( clock_gettime # i32 ( posix_const `CLOCK_REALTIME` ) # *u ts )
    ? != rc 0 { ( nurl_free ts ) ^ 0 } {}
    : i secs ( nurl_peek ts 0 )
    ( nurl_free ts )
    ^ secs
}

@ monotonic_ns → i {
    : s ts ( nurl_zalloc 16 )
    : i32 rc ( clock_gettime # i32 ( posix_const `CLOCK_MONOTONIC` ) # *u ts )
    ? != rc 0 { ( nurl_free ts ) ^ 0 } {}
    : i secs ( nurl_peek ts 0 )
    : i nsec ( nurl_peek ts 1 )
    ( nurl_free ts )
    ^ + * secs 1000000000 nsec
}

// Blocking `nanosleep` loop — retries on EINTR with the remaining
// time the kernel wrote into the second timespec. Negative / zero ms
// is a no-op. Allocates two 16-byte timespec buffers (req + rem) so
// EINTR retries preserve the unslept remainder.
@ __sleep_ms_blocking i ms → v {
    ? > ms 0 {
        : s req ( nurl_zalloc 16 )
        : i secs / ms 1000
        : i ms_rem - ms * secs 1000
        ( nurl_poke req 0 secs )
        ( nurl_poke req 1 * ms_rem 1000000 )
        : ~ b done F
        ~ ! done {
            : i32 rc ( nanosleep # *u req # *u req )
            ? == rc 0 {
                = done T
            } {
                : i e ( nurl_errno_get )
                ? != e ( posix_const `EINTR` ) {
                    // Any non-EINTR failure (EINVAL, EFAULT) is a programmer
                    // bug, not a transient — stop retrying rather than
                    // spin-loop. The remaining sleep is lost; callers that
                    // care should not feed in bogus durations.
                    = done T
                } {}
            }
        }
        ( nurl_free req )
    } {}
}

// Context-aware sleep: when called from inside a fiber, parks on
// the async runtime's timer wheel so the worker pthread keeps
// running other fibers. When called from a plain OS thread (or on
// WASI / Windows where the fiber runtime is stubbed), falls back to
// `nanosleep`-style blocking. The dispatch is invisible to the
// caller — same name, same signature, same observable wait time.
@ sleep_ms i ms → v {
    : i fcur ( nurl_fiber_current )
    ? != fcur 0 {
        : i unused ( nurl_fiber_sleep_ms ms )
    } {
        ( __sleep_ms_blocking ms )
    }
}

@ elapsed_ms_since i t0 → i {
    : i now ( monotonic_ns )
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

// ── Calendar helpers ─────────────────────────────────────────────────

// Proleptic Gregorian leap year: divisible by 4, except centuries,
// except every 400th.
@ is_leap_year i y → b {
    ? != ( __i_mod y 4 ) 0 { ^ F } {}
    ? != ( __i_mod y 100 ) 0 { ^ T } {}
    ^ == ( __i_mod y 400 ) 0
}

// Number of days in month `m` (1..12) of year `y`. February is
// leap-year aware. `m` outside 1..12 yields 31 (callers validate).
@ days_in_month i y i m → i {
    ? == m 2 { ^ ? ( is_leap_year y ) 29 28 } {}
    ? | | | == m 4 == m 6 == m 9 == m 11 { ^ 30 } {}
    ^ 31
}

// Validated civil-time constructor. Every field is range-checked (day
// against the actual month length, so 2023-02-29 is rejected but
// 2024-02-29 is accepted); out-of-range input → `ParseErr.BadFormat`.
//
// Returns the **Unix timestamp** (seconds), not a `Time`. A wide-payload
// `! T E` value is silently truncated when matched directly as
// `?? ( call ) { … }` (a compiler bug — binding the result to a `:`
// variable first is the working form); an `! i ParseErr` carries a
// narrow `i` payload and is immune. Pass the result to `time_from_unix`
// for the broken-down fields:
//   : !i ParseErr r ( time_make 2026 5 21 14 39 0 )
//   ?? r {
//     T secs → { : Time t ( time_from_unix secs )  … }
//     F e → …
//   }
@ time_make i year i month i day i hour i min i sec → !i ParseErr {
    ? | < month 1 > month 12
    { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? | < day 1 > day ( days_in_month year month )
    { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? | < hour 0 > hour 23
    { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? | < min 0 > min 59
    { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? | < sec 0 > sec 59
    { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ^ @ !i ParseErr { T ( time_to_unix @ Time { year month day hour min sec 0 0 } ) }
}

// Day of year, 1 (Jan 1) .. 365/366 (Dec 31).
@ time_yday Time t → i {
    : i d0 ( __days_from_civil . t year 1 1 )
    : i dn ( __days_from_civil . t year . t month . t day )
    ^ + - dn d0 1
}

// ── Comparison ───────────────────────────────────────────────────────
//
// All comparisons are by Unix-second value (sub-second `ns` is ignored
// — `time_from_unix` never populates it). Suitable for sorting /
// filtering timestamp columns in ETL.

@ time_cmp Time a Time b → i {
    : i ua ( time_to_unix a )
    : i ub ( time_to_unix b )
    ? < ua ub { ^ -1 } {}
    ? > ua ub { ^ 1 } {}
    ^ 0
}

@ time_eq Time a Time b → b {
    ^ == ( time_to_unix a ) ( time_to_unix b )
}

@ time_before Time a Time b → b {
    ^ < ( time_to_unix a ) ( time_to_unix b )
}

@ time_after Time a Time b → b {
    ^ > ( time_to_unix a ) ( time_to_unix b )
}

// ── Arithmetic ───────────────────────────────────────────────────────
//
// Add/subtract via the Unix-second axis, then re-derive the calendar
// fields — so `time_add_days t 1` correctly rolls over month and year
// boundaries (and leap days). Negative arguments subtract.

@ time_add_seconds Time t i secs → Time {
    ^ ( time_from_unix + ( time_to_unix t ) secs )
}

@ time_add_days Time t i days → Time {
    ^ ( time_from_unix + ( time_to_unix t ) * days 86400 )
}

// Signed second difference a − b.
@ time_diff_seconds Time a Time b → i {
    ^ - ( time_to_unix a ) ( time_to_unix b )
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

@ __push_3digit String out i n → v {
    ( string_push_char out + 48 / n 100 )
    ( string_push_char out + 48 / ( __i_mod n 100 ) 10 )
    ( string_push_char out + 48 ( __i_mod n 10 ) )
}

@ __wday_full i w → s {
    ? == w 0 { ^ `Sunday` } {}
    ? == w 1 { ^ `Monday` } {}
    ? == w 2 { ^ `Tuesday` } {}
    ? == w 3 { ^ `Wednesday` } {}
    ? == w 4 { ^ `Thursday` } {}
    ? == w 5 { ^ `Friday` } {}
    ? == w 6 { ^ `Saturday` } {}
    ^ `???`
}

@ __month_full i m → s {
    ? == m 1 { ^ `January` } {}
    ? == m 2 { ^ `February` } {}
    ? == m 3 { ^ `March` } {}
    ? == m 4 { ^ `April` } {}
    ? == m 5 { ^ `May` } {}
    ? == m 6 { ^ `June` } {}
    ? == m 7 { ^ `July` } {}
    ? == m 8 { ^ `August` } {}
    ? == m 9 { ^ `September` } {}
    ? == m 10 { ^ `October` } {}
    ? == m 11 { ^ `November` } {}
    ? == m 12 { ^ `December` } {}
    ^ `???`
}

// Emit one strftime directive byte `d` into `out`. Returns T if `d` is
// a recognised directive, F otherwise (the caller then emits the `%`
// and the byte verbatim). Supported: %Y %y %m %d %H %M %S %j %a %A
// %b %B %%.
@ __time_emit_directive String out Time t i d → b {
    ? == d 37 { ( string_push_char out 37 ) ^ T } {}
    ? == d 89 { ( __push_4digit out . t year ) ^ T } {}
    ? == d 121 { ( __push_2digit out ( __i_mod . t year 100 ) ) ^ T } {}
    ? == d 109 { ( __push_2digit out . t month ) ^ T } {}
    ? == d 100 { ( __push_2digit out . t day ) ^ T } {}
    ? == d 72 { ( __push_2digit out . t hour ) ^ T } {}
    ? == d 77 { ( __push_2digit out . t min ) ^ T } {}
    ? == d 83 { ( __push_2digit out . t sec ) ^ T } {}
    ? == d 106 { ( __push_3digit out ( time_yday t ) ) ^ T } {}
    ? == d 97 { ( string_push_str out ( __wday_name . t wday ) ) ^ T } {}
    ? == d 65 { ( string_push_str out ( __wday_full . t wday ) ) ^ T } {}
    ? == d 98 { ( string_push_str out ( __month_name . t month ) ) ^ T } {}
    ? == d 66 { ( string_push_str out ( __month_full . t month ) ) ^ T } {}
    ^ F
}

// strftime-style formatter. `fmt` is a borrowed raw `s`; the result is
// a fresh owned String. Directives: %Y (4-digit year), %y (2-digit
// year), %m %d %H %M %S (zero-padded 2-digit), %j (3-digit day of
// year), %a/%A (abbreviated/full weekday), %b/%B (abbreviated/full
// month), %% (literal percent). An unrecognised %X is copied verbatim.
// For the two common fixed shapes prefer `time_format_iso` /
// `time_format_http` — they skip the directive scan.
@ time_format Time t s fmt → String {
    : String out ( string_with_cap 32 )
    : i n ( nurl_str_len fmt )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_at fmt n i )
        ? & == c 37 < + i 1 n {
            : i d ( nurl_str_at fmt n + i 1 )
            ? ( __time_emit_directive out t d ) {} {
                ( string_push_char out 37 )
                ( string_push_char out d )
            }
            = i + i 2
        } {
            ( string_push_char out c )
            = i + i 1
        }
    }
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
    ^ == ( nurl_str_at p n idx ) target
}

@ __take_ndigits s p i start i count i max_idx → i {
    ? > + start count max_idx { ^ -1 } {}
    : ~ i acc 0
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k count {
        : i c ( nurl_str_at p max_idx + start k )
        ? & >= c 48 <= c 57 {
            = acc + * acc 10 - c 48
        } { = ok F }
        = k + k 1
    }
    ? ! ok { ^ -1 } {}
    ^ acc
}

@ time_parse_iso s p → !i ParseErr {
    : i n ( nurl_str_len p )
    ? < n 19 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    : i y ( __take_ndigits p 0 4 n )
    ? < y 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 4 45 ) { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    : i mo ( __take_ndigits p 5 2 n )
    ? < mo 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 7 45 ) { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    : i d ( __take_ndigits p 8 2 n )
    ? < d 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}

    : i sep ( nurl_str_at p n 10 )
    ? & != sep 84 != sep 116 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}

    : i hh ( __take_ndigits p 11 2 n )
    ? < hh 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 13 58 ) { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    : i mm ( __take_ndigits p 14 2 n )
    ? < mm 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? ! ( __char_at_eq p 16 58 ) { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    : i ss ( __take_ndigits p 17 2 n )
    ? < ss 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}

    : ~ i k 19
    // Optional fractional seconds (ignored, just consume).
    ? & < k n == ( nurl_str_at p n k ) 46 {
        = k + k 1
        ~ & < k n & >= ( nurl_str_at p n k ) 48 <= ( nurl_str_at p n k ) 57 {
            = k + k 1
        }
    } {}

    : ~ i offset_min 0
    ? < k n {
        : i tc ( nurl_str_at p n k )
        ? | == tc 90 == tc 122 {
            = k + k 1
        } {
            ? | == tc 43 == tc 45 {
                : i sign ? == tc 45 -1 1
                = k + k 1
                : i oh ( __take_ndigits p k 2 n )
                ? < oh 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
                = k + k 2
                ? & < k n == ( nurl_str_at p n k ) 58 { = k + k 1 } {}
                : i om ( __take_ndigits p k 2 n )
                ? < om 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
                = k + k 2
                = offset_min * sign + * oh 60 om
            } { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } }
        }
    } {}
    ? != k n { ^ @ !i ParseErr { F @ ParseErr { TrailingGarbage } } } {}

    : i unix_local ( time_to_unix @ Time { y mo d hh mm ss 0 0 } )
    : i unix_utc - unix_local * offset_min 60
    ^ @ !i ParseErr { T unix_utc }
}

// ── §12c HTTP-date / RFC 2822 date parsing ───────────────────────────
//
// The server FORMATS HTTP dates (time_format_http) but until now could
// not PARSE them — needed for `If-Modified-Since`, `If-Unmodified-Since`
// and cookie `Expires`. RFC 7231 §7.1.1.1 requires a recipient to accept
// all three historical forms, and email `Date:` (RFC 5322/2822) adds a
// numeric zone. All return UTC seconds since the Unix epoch in the
// `!i ParseErr` shape (pair with `time_from_unix` for fields), so they
// drop in next to `time_parse_iso`:
//
//   IMF-fixdate (preferred):  Sun, 06 Nov 1994 08:49:37 GMT
//   RFC 850 (obsolete):       Sunday, 06-Nov-94 08:49:37 GMT
//   asctime (obsolete):       Sun Nov  6 08:49:37 1994
//   RFC 2822 (email Date):    Mon, 02 Jan 2006 15:04:05 -0700
//
//   ( http_date_parse s )   → !i ParseErr   the three RFC 7231 forms (GMT)
//   ( rfc2822_parse   s )   → !i ParseErr   email Date, numeric / GMT zone
//
// A 2-digit RFC 850 year uses the POSIX sliding pivot: YY < 70 → 20YY,
// else 19YY. Obsolete alphabetic US zones (EST/PDT/…) in RFC 2822 are
// not resolved (their offset is ambiguous by the RFC's own admission) —
// only GMT/UT/UTC/Z (= +0000) and numeric ±HHMM offsets are accepted.

// Month abbreviation at p[off..off+3] → 1..12, or -1.
@ __month3_at s p i off i n → i {
    ? > + off 3 n { ^ -1 } {}
    : i c0 ( nurl_str_at p n off )
    : i c1 ( nurl_str_at p n + off 1 )
    : i c2 ( nurl_str_at p n + off 2 )
    // J: Jan/Jun/Jul · F: Feb · M: Mar/May · A: Apr/Aug · S: Sep · O: Oct
    // N: Nov · D: Dec  (compare the 2nd/3rd letters to disambiguate)
    ? == c0 74 {  // 'J'
        ? & == c1 97 == c2 110 { ^ 1 } {}  // Jan
        ? & == c1 117 == c2 110 { ^ 6 } {}  // Jun
        ? & == c1 117 == c2 108 { ^ 7 } {}  // Jul
        ^ -1
    } {}
    ? & & == c0 70 == c1 101 == c2 98 { ^ 2 } {}  // Feb
    ? == c0 77 {  // 'M'
        ? & == c1 97 == c2 114 { ^ 3 } {}  // Mar
        ? & == c1 97 == c2 121 { ^ 5 } {}  // May
        ^ -1
    } {}
    ? == c0 65 {  // 'A'
        ? & == c1 112 == c2 114 { ^ 4 } {}  // Apr
        ? & == c1 117 == c2 103 { ^ 8 } {}  // Aug
        ^ -1
    } {}
    ? & & == c0 83 == c1 101 == c2 112 { ^ 9 } {}  // Sep
    ? & & == c0 79 == c1 99 == c2 116 { ^ 10 } {}  // Oct
    ? & & == c0 78 == c1 111 == c2 118 { ^ 11 } {}  // Nov
    ? & & == c0 68 == c1 101 == c2 99 { ^ 12 } {}  // Dec
    ^ -1
}

// One token = a maximal run of non-(space/comma) bytes. Writes the
// token's [start,end) into a 2-slot scratch and returns the index just
// past it; -1 when no token remains from `from`.
@ __hd_token s p i n i from s out_start s out_end → i {
    : ~ i k from
    ~ & < k n | == ( nurl_str_at p n k ) 32 == ( nurl_str_at p n k ) 44 { = k + k 1 }
    ? >= k n { ^ -1 } {}
    : i st k
    ~ & < k n & != ( nurl_str_at p n k ) 32 != ( nurl_str_at p n k ) 44 { = k + k 1 }
    ( nurl_poke # s out_start 0 st )
    ( nurl_poke # s out_end 0 k )
    ^ k
}

@ __hd_all_digits s p i st i en → b {
    : ~ i k st
    : ~ b ok > en st
    ~ & ok < k en {
        : i c ( nurl_str_at p en k )
        ? & >= c 48 <= c 57 {} { = ok F }
        = k + k 1
    }
    ^ ok
}

@ __hd_index_of s p i st i en i ch → i {
    : ~ i k st
    ~ < k en { ? == ( nurl_str_at p en k ) ch { ^ k } {} = k + k 1 }
    ^ -1
}

// Shared flexible parser for every form above. Tokenizes on space/comma,
// classifies each token (month name / `HH:MM:SS` / `DD-Mon-YY` / number /
// zone), then folds to UTC seconds. `require_zone` makes a missing zone
// an error (RFC 2822 mandates one; HTTP forms always end in GMT).
@ __parse_date_flex s p b require_zone → !i ParseErr {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}
    : s ts ( nurl_zalloc 8 )
    : s te ( nurl_zalloc 8 )
    : ~ i pos 0
    : ~ i day -1
    : ~ i mon -1
    : ~ i year -1
    : ~ i hh -1
    : ~ i mm 0
    : ~ i ss 0
    : ~ i off_min 0
    : ~ b have_zone F
    : ~ b bad F
    : ~ b going T
    ~ & going ! bad {
        : i nxt ( __hd_token p n pos ts te )
        ? < nxt 0 { = going F } {
            = pos nxt
            : i st ( nurl_peek ts 0 )
            : i en ( nurl_peek te 0 )
            : i len - en st
            : i m3 ( __month3_at p st n )
            : i colon ( __hd_index_of p st en 58 )
            : i dash ( __hd_index_of p st en 45 )
            : i c0 ( nurl_str_at p n st )
            ? >= m3 0 {
                // bare month name token
                ? < mon 0 { = mon m3 } {}
            } {
                ? >= colon 0 {
                    // HH:MM[:SS]
                    : i h ( __take_ndigits p st 2 n )
                    : i m2c ( __hd_index_of p + colon 1 en 58 )
                    : i mi ( __take_ndigits p + colon 1 2 n )
                    ? | < h 0 < mi 0 { = bad T } {
                        = hh h = mm mi
                        ? >= m2c 0 {
                            : i se ( __take_ndigits p + m2c 1 2 n )
                            ? < se 0 { = bad T } { = ss se }
                        } {}
                    }
                } {
                    ? & >= dash 0 >= ( __month3_at p + dash 1 n ) 0 {
                        // RFC 850 DD-Mon-YY
                        : i d ( __take_ndigits p st 2 n )
                        : i mn ( __month3_at p + dash 1 n )
                        : i dash2 ( __hd_index_of p + dash 1 en 45 )
                        ? | | < d 0 < mn 0 < dash2 0 { = bad T } {
                            : i yy ( __take_ndigits p + dash2 1 2 n )
                            ? < yy 0 { = bad T } {
                                = day d = mon mn
                                = year ? < yy 70 + 2000 yy + 1900 yy
                            }
                        }
                    } {
                        ? | | == c0 43 == c0 45 & ( __hd_all_digits p + st 1 en ) >= len 5 {
                            // numeric zone ±HHMM
                            : i sign ? == c0 45 -1 1
                            : i oh ( __take_ndigits p + st 1 2 n )
                            : i om ( __take_ndigits p + st 3 2 n )
                            ? | < oh 0 < om 0 { = bad T } {
                                = off_min * sign + * oh 60 om = have_zone T
                            }
                        } {
                            ? ( __hd_all_digits p st en ) {
                                // a number: 4 digits → year, else day
                                : i v ( __take_ndigits p st len n )
                                ? < v 0 { = bad T } {
                                    ? & == len 4 < year 0 { = year v } {
                                        ? < day 0 { = day v } {
                                            ? < year 0 { = year v } {}
                                        }
                                    }
                                }
                            } {
                                // alphabetic zone: GMT/UT/UTC/Z → 0; any
                                // other word (e.g. the weekday "Sun") is
                                // simply ignored. An alpha zone resolves
                                // only for the UTC set.
                                ? ( __hd_zone_is_utc p st en )
                                { = have_zone T } {}
                            }
                        }
                    }
                }
            }
        }
    }
    ( nurl_free # s ts )
    ( nurl_free # s te )
    ? bad { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? | | | < day 0 < mon 0 < year 0 < hh 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ? & require_zone ! have_zone { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    : !i ParseErr civ ( time_make year mon day hh mm ss )
    ^ ?? civ {
        T unix_local → @ !i ParseErr { T - unix_local * off_min 60 }
        F e → @ !i ParseErr { F e }
    }
}

// True iff p[st..en) is GMT / UT / UTC / Z / Z-as-+0000 (all = UTC).
@ __hd_zone_is_utc s p i st i en → b {
    : i len - en st
    ? & == len 1 == ( nurl_str_at p en st ) 90 { ^ T } {}  // Z
    ? & & == len 2 == ( nurl_str_at p en st ) 85 == ( nurl_str_at p en + st 1 ) 84 { ^ T } {}  // UT
    ? & & & == len 3 == ( nurl_str_at p en st ) 71 == ( nurl_str_at p en + st 1 ) 77 == ( nurl_str_at p en + st 2 ) 84 { ^ T } {}  // GMT
    ? & & & == len 3 == ( nurl_str_at p en st ) 85 == ( nurl_str_at p en + st 1 ) 84 == ( nurl_str_at p en + st 2 ) 67 { ^ T } {}  // UTC
    ^ F
}

@ http_date_parse s p → !i ParseErr {
    ^ ( __parse_date_flex p F )
}

@ rfc2822_parse s p → !i ParseErr {
    ^ ( __parse_date_flex p T )
}

// ── §12b Timezones / DST — POSIX TZ-string rules ─────────────────────
//
// Local-time conversion with daylight-saving transitions, driven by a
// POSIX TZ string (the `TZ` env-var format, e.g. `EST5EDT,M3.2.0,M11.1.0`
// or `CET-1CEST,M3.5.0,M10.5.0/3`). This is the format IANA tzdata
// compiles each zone's final rule into, and it covers every real DST
// regime in use (US / EU / Australia all use the `Mm.w.d` rule form).
//
// NOT in scope (and not needed for conversion): the full IANA tzdata
// database keyed by region name like "America/New_York", and historical
// rule changes — a single POSIX TZ string encodes one current ruleset.
// The caller supplies the TZ string (read it from the `TZ` env var, a
// config value, or hard-code the zone you target).
//
//   ( tz_utc )                       → TimeZone     UTC, no DST
//   ( tz_fixed off_secs )            → TimeZone     fixed offset east of UTC
//   ( tz_parse posix_str )           → ! TimeZone ParseErr
//   ( tz_offset_at tz utc_secs )     → i            seconds east of UTC in effect
//   ( tz_is_dst tz utc_secs )        → b            is DST active at that instant
//   ( time_from_unix_tz utc tz )     → Time         broken-down LOCAL fields
//   ( time_now_tz tz )               → Time         local "now"
//   ( time_to_unix_tz local tz )     → i            local civil fields → UTC secs
//   ( time_format_offset t off )     → String       ISO 8601 + numeric offset
//   ( time_format_iso_tz utc tz )    → String       one-shot UTC instant → local ISO
//
// TimeZone is a plain value type (all integer fields) — copy it freely,
// no free needed. Only the `Mm.w.d[/time]` rule form is parsed; the
// `Jn` / `n` (Julian-day) forms return ParseErr.BadFormat. Ambiguous or
// nonexistent local times across a transition resolve to the
// standard-time interpretation.

: TimeZone {
    i std_off  // seconds east of UTC during standard time
    i dst_off  // seconds east of UTC during DST (== std_off when no DST)
    i has_dst  // 0 / 1
    i s_mon  // DST start rule: month 1..12
    i s_week  // week 1..5 (5 = last)
    i s_dow  // weekday 0=Sun..6=Sat
    i s_time  // seconds after local midnight (default 02:00:00)
    i e_mon  // DST end rule
    i e_week
    i e_dow
    i e_time
}

: __TzOff { i secs i endpos }
: __TzRule { i mon i week i dow i time i endpos i ok }

@ __tz_is_alpha i c → b {
    ^ | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ __tz_is_digit i c → b {
    ^ & >= c 48 <= c 57
}

// Skip a zone abbreviation: a `<...>` quoted name, or a run of letters.
@ __tz_skip_name s buf i pos i n → i {
    ? & < pos n == ( nurl_str_at buf n pos ) 60 {  // '<'
        : ~ i p + pos 1
        ~ & < p n != ( nurl_str_at buf n p ) 62 { = p + p 1 }
        ? & < p n == ( nurl_str_at buf n p ) 62 { = p + p 1 } {}
        ^ p
    } {}
    : ~ i p pos
    ~ & < p n ( __tz_is_alpha ( nurl_str_at buf n p ) ) { = p + p 1 }
    ^ p
}

// Parse `h[:m[:s]]` (no sign). endpos == pos when no digits were read.
@ __tz_parse_hms s buf i pos → __TzOff {
    : i n ( nurl_str_len buf )
    : ~ i p pos
    : ~ i hh 0
    : ~ b any F
    ~ ( __tz_is_digit ( nurl_str_at buf n p ) ) { = hh + * hh 10 - ( nurl_str_at buf n p ) 48 = p + p 1 = any T }
    ? ! any { ^ @ __TzOff { 0 pos } } {}
    : ~ i mm 0
    ? == ( nurl_str_at buf n p ) 58 {  // ':'
        = p + p 1
        ~ ( __tz_is_digit ( nurl_str_at buf n p ) ) { = mm + * mm 10 - ( nurl_str_at buf n p ) 48 = p + p 1 }
    } {}
    : ~ i ss 0
    ? == ( nurl_str_at buf n p ) 58 {
        = p + p 1
        ~ ( __tz_is_digit ( nurl_str_at buf n p ) ) { = ss + * ss 10 - ( nurl_str_at buf n p ) 48 = p + p 1 }
    } {}
    : i secs + + * hh 3600 * mm 60 ss
    ^ @ __TzOff { secs p }
}

// Parse a POSIX offset `[+|-]h[:m[:s]]` → seconds EAST of UTC. POSIX
// offsets are seconds WEST (added to local to reach UTC), so the sign is
// inverted here. endpos == pos when no offset is present.
@ __tz_parse_offset s buf i pos → __TzOff {
    : i n ( nurl_str_len buf )
    : ~ i p pos
    : ~ i sign 1
    : i c0 ( nurl_str_at buf n p )
    ? == c0 45 { = sign -1 = p + p 1 } {}  // '-'
    ? == c0 43 { = p + p 1 } {}  // '+'
    : __TzOff h ( __tz_parse_hms buf p )
    ? == . h endpos p { ^ @ __TzOff { 0 pos } } {}
    : i east * -1 * sign . h secs
    ^ @ __TzOff { east . h endpos }
}

// Parse one `Mm.w.d[/time]` transition rule. ok == 0 on any deviation
// (including the unsupported Jn / n forms).
@ __tz_parse_rule s buf i pos i n → __TzRule {
    : ~ i p pos
    ? | >= p n != ( nurl_str_at buf n p ) 77 { ^ @ __TzRule { 0 0 0 7200 p 0 } } {}  // 'M'
    = p + p 1
    : ~ i mon 0
    : ~ b d1 F
    ~ & < p n ( __tz_is_digit ( nurl_str_at buf n p ) ) { = mon + * mon 10 - ( nurl_str_at buf n p ) 48 = p + p 1 = d1 T }
    ? | ! d1 != ( nurl_str_at buf n p ) 46 { ^ @ __TzRule { 0 0 0 7200 p 0 } } {}  // '.'
    = p + p 1
    : ~ i week 0
    : ~ b d2 F
    ~ & < p n ( __tz_is_digit ( nurl_str_at buf n p ) ) { = week + * week 10 - ( nurl_str_at buf n p ) 48 = p + p 1 = d2 T }
    ? | ! d2 != ( nurl_str_at buf n p ) 46 { ^ @ __TzRule { 0 0 0 7200 p 0 } } {}  // '.'
    = p + p 1
    : ~ i dow 0
    : ~ b d3 F
    ~ & < p n ( __tz_is_digit ( nurl_str_at buf n p ) ) { = dow + * dow 10 - ( nurl_str_at buf n p ) 48 = p + p 1 = d3 T }
    ? ! d3 { ^ @ __TzRule { 0 0 0 7200 p 0 } } {}
    : ~ i tsec 7200
    ? & < p n == ( nurl_str_at buf n p ) 47 {  // '/'
        = p + p 1
        : __TzOff th ( __tz_parse_hms buf p )
        ? != . th endpos p { = tsec . th secs = p . th endpos } {}
    } {}
    ? | | | < mon 1 > mon 12 | < week 1 > week 5 | < dow 0 > dow 6 {
        ^ @ __TzRule { 0 0 0 7200 p 0 }
    } {}
    ^ @ __TzRule { mon week dow tsec p 1 }
}

@ tz_utc → TimeZone {
    ^ @ TimeZone { 0 0 0 0 0 0 7200 0 0 0 7200 }
}

@ tz_fixed i off → TimeZone {
    ^ @ TimeZone { off off 0 0 0 0 7200 0 0 0 7200 }
}

@ tz_parse s p → !TimeZone ParseErr {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ @ !TimeZone ParseErr { F @ ParseErr { Empty } } } {}
    : ~ i pos 0
    = pos ( __tz_skip_name p pos n )
    : __TzOff so ( __tz_parse_offset p pos )
    ? == . so endpos pos { ^ @ !TimeZone ParseErr { F @ ParseErr { BadFormat } } } {}
    : i std_off . so secs
    = pos . so endpos
    : ~ i has_dst 0
    : ~ i dst_off std_off
    ? & < pos n != ( nurl_str_at p n pos ) 44 {  // not ',' → DST abbrev present
        = has_dst 1
        = pos ( __tz_skip_name p pos n )
        : __TzOff doff ( __tz_parse_offset p pos )
        ? == . doff endpos pos {
            = dst_off + std_off 3600
        } {
            = dst_off . doff secs
            = pos . doff endpos
        }
    } {}
    : ~ i s_mon 0
    : ~ i s_week 0
    : ~ i s_dow 0
    : ~ i s_time 7200
    : ~ i e_mon 0
    : ~ i e_week 0
    : ~ i e_dow 0
    : ~ i e_time 7200
    ? == has_dst 1 {
        ? | >= pos n != ( nurl_str_at p n pos ) 44 { ^ @ !TimeZone ParseErr { F @ ParseErr { BadFormat } } } {}
        = pos + pos 1
        : __TzRule r1 ( __tz_parse_rule p pos n )
        ? == . r1 ok 0 { ^ @ !TimeZone ParseErr { F @ ParseErr { BadFormat } } } {}
        = s_mon . r1 mon
        = s_week . r1 week
        = s_dow . r1 dow
        = s_time . r1 time
        = pos . r1 endpos
        ? | >= pos n != ( nurl_str_at p n pos ) 44 { ^ @ !TimeZone ParseErr { F @ ParseErr { BadFormat } } } {}
        = pos + pos 1
        : __TzRule r2 ( __tz_parse_rule p pos n )
        ? == . r2 ok 0 { ^ @ !TimeZone ParseErr { F @ ParseErr { BadFormat } } } {}
        = e_mon . r2 mon
        = e_week . r2 week
        = e_dow . r2 dow
        = e_time . r2 time
        = pos . r2 endpos
    } {}
    ^ @ !TimeZone ParseErr { T @ TimeZone { std_off dst_off has_dst s_mon s_week s_dow s_time e_mon e_week e_dow e_time } }
}

// Day-of-month of the `week`-th `dow` (0=Sun) in (year, mon). week 1..4
// selects the n-th; week 5 (or any overshoot) selects the last.
@ __tz_nth_dow i year i mon i week i dow → i {
    : i days1 ( __days_from_civil year mon 1 )
    : i wday1 ( __i_mod + days1 4 7 )
    : i first + 1 ( __i_mod - + dow 7 wday1 7 )
    : i cand + first * - week 1 7
    : i dim ( days_in_month year mon )
    ? > cand dim { ^ - cand 7 } {}
    ^ cand
}

// UTC instant of a transition in `year`. which: 0 = DST start, 1 = end.
// The rule time is local; just before the START it is standard time, and
// just before the END it is daylight time — so we subtract the offset in
// effect immediately before the transition.
@ __tz_trans_utc TimeZone tz i year i which → i {
    : i mon ? == which 0 . tz s_mon . tz e_mon
    : i week ? == which 0 . tz s_week . tz e_week
    : i dow ? == which 0 . tz s_dow . tz e_dow
    : i tsec ? == which 0 . tz s_time . tz e_time
    : i dom ( __tz_nth_dow year mon week dow )
    : i localdays ( __days_from_civil year mon dom )
    : i localsecs + * localdays 86400 tsec
    : i off ? == which 0 . tz std_off . tz dst_off
    ^ - localsecs off
}

@ tz_is_dst TimeZone tz i utc → b {
    ? == . tz has_dst 0 { ^ F } {}
    : Time u ( time_from_unix utc )
    : i start ( __tz_trans_utc tz . u year 0 )
    : i end ( __tz_trans_utc tz . u year 1 )
    ? < start end { ^ & >= utc start < utc end } {}
    // Southern hemisphere: DST spans the year boundary.
    ^ | >= utc start < utc end
}

@ tz_offset_at TimeZone tz i utc → i {
    ? ( tz_is_dst tz utc ) { ^ . tz dst_off } {}
    ^ . tz std_off
}

@ time_from_unix_tz i utc TimeZone tz → Time {
    ^ ( time_from_unix + utc ( tz_offset_at tz utc ) )
}

@ time_now_tz TimeZone tz → Time {
    ^ ( time_from_unix_tz ( now_seconds ) tz )
}

// Interpret broken-down LOCAL fields as a wall-clock time in `tz` and
// return the UTC timestamp. Guesses with the standard offset, then
// refines to the DST offset if that instant falls inside the DST window.
@ time_to_unix_tz Time t TimeZone tz → i {
    : i localsecs ( time_to_unix t )
    : i guess - localsecs . tz std_off
    ? ( tz_is_dst tz guess ) { ^ - localsecs . tz dst_off } {}
    ^ guess
}

@ __tz_push_offset String out i off → v {
    ? == off 0 {
        ( string_push_char out 90 )  // 'Z'
    } {
        : i a ? < off 0 - 0 off off
        : i sign ? < off 0 45 43
        ( string_push_char out sign )
        : i hh / a 3600
        : i mm / - a * hh 3600 60
        ( __push_2digit out hh )
        ( string_push_char out 58 )  // ':'
        ( __push_2digit out mm )
    }
}

// ISO 8601 with a numeric UTC offset, e.g. "2026-07-01T08:30:00-04:00"
// (or "…Z" when off == 0). `t` must already hold LOCAL fields.
@ time_format_offset Time t i off → String {
    : String out ( string_with_cap 32 )
    ( __push_4digit out . t year )
    ( string_push_char out 45 )
    ( __push_2digit out . t month )
    ( string_push_char out 45 )
    ( __push_2digit out . t day )
    ( string_push_char out 84 )  // 'T'
    ( __push_2digit out . t hour )
    ( string_push_char out 58 )
    ( __push_2digit out . t min )
    ( string_push_char out 58 )
    ( __push_2digit out . t sec )
    ( __tz_push_offset out off )
    ^ out
}

// One-shot: a UTC instant → local ISO 8601 with the offset for `tz`.
@ time_format_iso_tz i utc TimeZone tz → String {
    : i off ( tz_offset_at tz utc )
    : Time t ( time_from_unix + utc off )
    ^ ( time_format_offset t off )
}
