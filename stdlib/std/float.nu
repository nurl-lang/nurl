// stdlib/std/float.nu — IEEE-754 double helpers (libm bridge)
//
// Thin wrappers over the runtime libm bindings (`nurl_sqrt`, `nurl_sin`, …).
// All trigonometric functions take/return radians; `atan2 y x` returns the
// principal angle of the point (x, y).
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

// ── Constants ──────────────────────────────────────────────────────

: f PI       3.141592653589793
: f E        2.718281828459045
: f TAU      6.283185307179586
: f PI_2     1.5707963267948966
: f SQRT_2   1.4142135623730951
: f LN_2     0.6931471805599453
: f LN_10    2.302585092994046

// ── libm wrappers ──────────────────────────────────────────────────

@ float_abs   f x → f { ^ ( nurl_fabs  x ) }
@ float_sqrt  f x → f { ^ ( nurl_sqrt  x ) }
@ float_floor f x → f { ^ ( nurl_floor x ) }
@ float_ceil  f x → f { ^ ( nurl_ceil  x ) }
@ float_round f x → f { ^ ( nurl_round x ) }
@ float_log   f x → f { ^ ( nurl_log   x ) }
@ float_exp   f x → f { ^ ( nurl_exp   x ) }
@ float_sin   f x → f { ^ ( nurl_sin   x ) }
@ float_cos   f x → f { ^ ( nurl_cos   x ) }
@ float_tan   f x → f { ^ ( nurl_tan   x ) }

@ float_pow   f x f y → f { ^ ( nurl_pow   x y ) }
@ float_atan2 f y f x → f { ^ ( nurl_atan2 y x ) }

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
// Uses the runtime sideband: nurl_str_to_float_safe returns 1/0 ok-flag
// and stashes the parsed value in a static slot retrievable via
// nurl_str_float_value. Single-threaded only, but consistent with the
// rest of NURL's runtime conventions (see `nurl_get_last_type`).

@ float_parse s str → ! f ParseErr {
  ? == 0 ( nurl_str_len str ) {
    ^ @ ! f ParseErr { F @ ParseErr { Empty } }
  } {}
  : i ok ( nurl_str_to_float_safe str )
  ? == ok 0 {
    ^ @ ! f ParseErr { F @ ParseErr { BadFormat } }
  } {}
  ^ @ ! f ParseErr { T ( nurl_str_float_value ) }
}

// String → float without error info (legacy convenience).
@ float_to_string f x → s {
  ^ ( nurl_str_float x )
}
