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
//   - Calendar arithmetic is UTC only. No timezone or DST handling —
//     callers that need local time should keep the offset themselves.

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
& `c` @ nanosleep     *u req         *u rem → i32

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
        : i c ( nurl_str_get fmt i )
        ? & == c 37 < + i 1 n {
            : i d ( nurl_str_get fmt + i 1 )
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

    : i sep ( nurl_str_get p 10 )
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
                ? < oh 0 { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
                = k + k 2
                ? & < k n == ( nurl_str_get p k ) 58 { = k + k 1 } {}
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
