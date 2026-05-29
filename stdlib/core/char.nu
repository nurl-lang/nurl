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
//   ( is_upper     i c )  → i      1 if A-Z, else 0
//   ( is_lower     i c )  → i      1 if a-z, else 0
//   ( is_hexdigit  i c )  → i      1 if 0-9 A-F a-f, else 0
//   ( to_upper_ascii i c )→ i      a-z → A-Z; others unchanged
//   ( to_lower_ascii i c )→ i      A-Z → a-z; others unchanged
//   ( hex_val      i c )  → i      0-15 for a hex digit, else -1
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

// NB: the older predicates above (is_alpha / is_digit / …) end in
// `# i <bool-expr>`, which sign-extends the i1 true to -1 rather than 1
// — harmless for their `!= 0` callers but it contradicts the "→ 1"
// contract. The predicates below normalise to a canonical 1/0 via the
// ternary value-form so they can be compared against 1 directly.
@ is_upper i c → i {
    ^ ? & >= c 65 <= c 90 1 0
}

@ is_lower i c → i {
    ^ ? & >= c 97 <= c 122 1 0
}

// 0-9 (48-57) OR A-F (65-70) OR a-f (97-102) — the C `isxdigit` table.
@ is_hexdigit i c → i {
    ^ ? | | & >= c 48 <= c 57 & >= c 65 <= c 70 & >= c 97 <= c 102 1 0
}

// ASCII case folding. Non-letter bytes pass through unchanged; no
// locale-specific or Unicode mappings.
@ to_upper_ascii i c → i {
    ? != ( is_lower c ) 0 { ^ - c 32 } {}
    ^ c
}

@ to_lower_ascii i c → i {
    ? != ( is_upper c ) 0 { ^ + c 32 } {}
    ^ c
}

// Numeric value 0-15 of a hex-digit byte; -1 for any non-hex byte.
@ hex_val i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}
    ? & >= c 65 <= c 70 { ^ + - c 65 10 } {}
    ? & >= c 97 <= c 102 { ^ + - c 97 10 } {}
    ^ -1
}
