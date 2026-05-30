// stdlib/std/float.nu — IEEE-754 double helpers (libm bridge)
//
// Pure-NURL FFI to libm — `sqrt` / `fabs` / `sin` / `cos` / … are
// declared directly via `& `m` @ … → …` below, no `runtime.c`
// pass-through. All trigonometric functions take/return radians;
// `atan2 y x` returns the principal angle of the point (x, y).
//
//   ( float_abs   x )       → f
//   ( float_sqrt  x )       → f
//   ( float_floor x )       → f
//   ( float_ceil  x )       → f
//   ( float_round x )       → f      half-away-from-zero
//   ( float_pow   x y )     → f      x^y, allows fractional and negative y
//   ( float_log   x )       → f      natural log
//   ( float_exp   x )       → f      e^x
//   ( float_sin / cos / tan x ) → f
//   ( float_atan2 y x )     → f      angle of (x, y), range [-π, π]
//   ( float_trunc x )       → f      round toward zero
//   ( float_cbrt  x )       → f      real cube root (handles x < 0)
//   ( float_hypot x y )     → f      sqrt(x²+y²) without over/underflow
//   ( float_log2  x )       → f      base-2 log
//   ( float_log10 x )       → f      base-10 log
//   ( float_sign  x )       → f      -1.0 / 0.0 / +1.0 (0 and NaN → 0.0)
//
// Predicates (no libm needed — pure NURL):
//   ( float_is_nan x )      → b      NaN ≠ itself by IEEE-754
//   ( float_is_inf x )      → b      +∞ or −∞
//
// Strict parser:
//   ( float_parse s )       → ! f ParseErr
//     - empty string                → Empty
//     - leading whitespace ok       → BadFormat only on real malformed input
//     - trailing garbage / overflow → BadFormat
//
// Constants exported as module-level globals:
//   PI       = 3.141592653589793
//   E        = 2.718281828459045
//   TAU      = 2·π = 6.283185307179586
//   PI_2     = π/2
//   SQRT_2   = 1.4142135623730951
//   LN_2     = 0.6931471805599453
//   LN_10    = 2.302585092994046

$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/posix.nu`  // posix_const + nurl_errno_get for strtod ERANGE detection

// ── Constants ──────────────────────────────────────────────────────

: f PI 3.141592653589793
: f E 2.718281828459045
: f TAU 6.283185307179586
: f PI_2 1.5707963267948966
: f SQRT_2 1.4142135623730951
: f LN_2 0.6931471805599453
: f LN_10 2.302585092994046

// ── libm FFI (pure NURL — direct linker calls to libm) ────────────
//
// On glibc/musl/macOS-libsystem these are plain `double f(double)`
// exports from libm.so / libSystem; on Windows MSVCRT/UCRT they're
// part of the C runtime and resolve under the same name. `m` is
// in `__ffi_lib_check`'s whitelist so no `stdlib/runtime.m`
// sentinel is needed.

& `m` @ sqrt f x → f

& `m` @ fabs f x → f

& `m` @ floor f x → f

& `m` @ ceil f x → f

& `m` @ round f x → f

& `m` @ log f x → f

& `m` @ exp f x → f

& `m` @ sin f x → f

& `m` @ cos f x → f

& `m` @ tan f x → f

& `m` @ pow f x f y → f

& `m` @ atan2 f y f x → f

& `m` @ trunc f x → f
& `m` @ cbrt f x → f
& `m` @ hypot f x f y → f
& `m` @ log2 f x → f
& `m` @ log10 f x → f

// ── float_* wrappers ──────────────────────────────────────────────

@ float_abs f x → f { ^ ( fabs x ) }

@ float_sqrt f x → f { ^ ( sqrt x ) }

@ float_floor f x → f { ^ ( floor x ) }

@ float_ceil f x → f { ^ ( ceil x ) }

@ float_round f x → f { ^ ( round x ) }

@ float_log f x → f { ^ ( log x ) }

@ float_exp f x → f { ^ ( exp x ) }

@ float_sin f x → f { ^ ( sin x ) }

@ float_cos f x → f { ^ ( cos x ) }

@ float_tan f x → f { ^ ( tan x ) }

@ float_pow f x f y → f { ^ ( pow x y ) }

@ float_atan2 f y f x → f { ^ ( atan2 y x ) }

// Round toward zero (drop the fractional part). Distinct from floor:
// trunc(-2.7) = -2.0 where floor(-2.7) = -3.0.
@ float_trunc f x → f { ^ ( trunc x ) }

// Real cube root — handles negative inputs (cbrt(-8) = -2.0), unlike
// pow(x, 1.0/3.0) which is NaN for x < 0.
@ float_cbrt f x → f { ^ ( cbrt x ) }

// sqrt(x*x + y*y) without intermediate overflow/underflow (libm hypot).
@ float_hypot f x f y → f { ^ ( hypot x y ) }

// Base-2 / base-10 logarithms (libm). Domain error (x <= 0) yields the
// platform libm result (-inf at 0, NaN below) — probe with float_is_*.
@ float_log2 f x → f { ^ ( log2 x ) }
@ float_log10 f x → f { ^ ( log10 x ) }

// Sign as a float: -1.0 / 0.0 / +1.0. Zero and NaN both map to 0.0
// (NaN compares false to everything).
@ float_sign f x → f {
    ? < x 0.0 { ^ - 0.0 1.0 } {}
    ? > x 0.0 { ^ 1.0 } {}
    ^ 0.0
}

// ── Predicates ─────────────────────────────────────────────────────

// NURL's `!=` lowers to `fcmp one` (ordered), so the usual `x != x`
// trick can't detect NaN. Defer to libm via the runtime helper.
@ float_is_nan f x → b {
    ^ != 0 ( nurl_is_nan x )
}

@ float_is_inf f x → b {
    ^ != 0 ( nurl_is_inf x )
}

// ── Strict parser ──────────────────────────────────────────────────
//
// Direct FFI to libc `strtod` — PURIFY §11 batch (2026-05-24) eliminated
// the runtime sideband (`nurl_str_to_float_safe` + `nurl_str_float_value`
// + static `g_last_parsed_float`). Strictness is enforced here:
//
//   - empty input                                → Empty
//   - leading whitespace ok, but at least one non-WS must follow → BadFormat
//   - no digits consumed (`endptr == str_after_ws`)              → BadFormat
//   - errno = ERANGE on overflow / underflow                     → BadFormat
//   - non-whitespace trailing garbage                            → BadFormat

@ float_parse s str → !f ParseErr {
    : i n ( nurl_str_len str )
    ? == n 0 { ^ @ !f ParseErr { F @ ParseErr { Empty } } } {}
    // strtod skips leading whitespace itself, but we still need to
    // detect "all whitespace" inputs so the caller can distinguish
    // Empty from BadFormat. Walk past spaces / tabs explicitly.
    : ~ i pre 0
    : ~ b stopped F
    ~ & < pre n ! stopped {
        : i c ( nurl_str_get str pre )
        ? || == c 32 == c 9 { = pre + pre 1 } { = stopped T }
    }
    ? >= pre n { ^ @ !f ParseErr { F @ ParseErr { Empty } } } {}

    : s ep_buf ( nurl_alloc 8 )
    ? == # i ep_buf 0 { ^ @ !f ParseErr { F @ ParseErr { BadFormat } } } {}
    ( nurl_poke ep_buf 0 0 )
    ( nurl_errno_set 0 )
    : f v ( strtod str # *u ep_buf )
    : i end ( nurl_peek ep_buf 0 )
    ( nurl_free ep_buf )

    // No digits consumed: endptr stayed at the first non-whitespace
    // byte (which strtod's internal whitespace skip reached).
    : i sptr + # i str pre
    ? == end sptr { ^ @ !f ParseErr { F @ ParseErr { BadFormat } } } {}

    // Out-of-range overflow / underflow.
    : i e ( nurl_errno_get )
    ? == e ( posix_const `ERANGE` ) {
        ^ @ !f ParseErr { F @ ParseErr { BadFormat } }
    } {}

    // Trailing garbage check: skip whitespace at endptr, then require
    // NUL terminator. NURL has no direct *u read-byte primitive in
    // this context — convert end back to an offset and re-read via
    // `nurl_str_get` which is bounds-aware.
    : i tail_off - end # i str
    : ~ i tk tail_off
    ~ < tk n {
        : i tc ( nurl_str_get str tk )
        ? || == tc 32 == tc 9 { = tk + tk 1 } {
            ^ @ !f ParseErr { F @ ParseErr { BadFormat } }
        }
    }
    ^ @ !f ParseErr { T v }
}

// String → float without error info (legacy convenience).
@ float_to_string f x → s {
    ^ ( nurl_str_float x )
}
