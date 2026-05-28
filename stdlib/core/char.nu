// stdlib/core/char.nu — ASCII character classification (pure NURL).
//
// Encodes the same byte ranges as `<ctype.h>` under the "C" locale
// (ASCII-only).
//
// API (i64 → i64):
//
//   ( is_alpha     i c )  → i      1 if A-Z or a-z, else 0
//   ( is_digit     i c )  → i      1 if 0-9, else 0
//   ( is_space     i c )  → i      1 if ' ' or \t \n \v \f \r, else 0
//   ( is_alnum_us  i c )  → i      1 if alpha, digit, or '_', else 0
//
// Non-ASCII bytes (≥128) and negative values return 0 from every
// predicate — matching the C ctype.h behaviour for unsigned-char
// inputs in the "C" locale.

@ is_alpha i c → i {
    ^ # i | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ is_digit i c → i {
    ^ # i & >= c 48 <= c 57
}

// ' ' (32) OR the contiguous run \t \n \v \f \r (9-13) — exactly the
// C `isspace` table in the "C" locale.
@ is_space i c → i {
    ^ # i | == c 32 & >= c 9 <= c 13
}

// alpha + digit + '_' (95). Underscore is the NURL identifier-
// continuation character; the trailing `_us` disambiguates it from a
// hypothetical strict-isalnum.
@ is_alnum_us i c → i {
    ^ # i | | != ( is_alpha c ) 0 != ( is_digit c ) 0 == c 95
}
