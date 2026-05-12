// stdlib/std/encode.nu — hex + base64 encoding (RFC 4648)
//
// All public functions take a raw `s` (NUL-terminated; for an owned
// String use `( string_data str )`) and return either an owned `String`
// or `! String ParseErr`. Decoded output is also a `String` — fine for
// text payloads, but binary data containing NUL bytes will be truncated
// by `string_data`-based consumers (the underlying buffer keeps the full
// length in `string_len`, so manual byte-loops still work).
//
//   ( hex_encode s )           → String              lowercase, 2 chars/byte
//   ( hex_decode s )           → ! String ParseErr   accepts upper/lower
//   ( b64_encode s )           → String              standard alphabet, padded
//   ( b64_encode_len s i )     → String              binary-safe (NUL ok)
//   ( b64_encode_vec (Vec u) ) → String              binary-safe
//   ( b64_decode s )           → ! String ParseErr   standard, padding optional
//   ( b64_url_encode s )       → String              URL-safe (- _), no padding
//   ( b64_url_decode s )       → ! String ParseErr   URL-safe, padding optional

$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

// ── Hex ────────────────────────────────────────────────────────────

@ __hex_digit i n → i {
  // 0-9 → '0' (48), 10-15 → 'a' (97)
  ? < n 10 { ^ + 48 n } {}
  ^ + 87 n
}

@ hex_encode s str → String {
  : i len ( nurl_str_len str )
  : String out ( string_with_cap * len 2 )
  : ~ i i 0
  ~ < i len {
    : i b ( nurl_str_get str i )
    : i hi ( __hex_digit & 15 / b 16 )
    : i lo ( __hex_digit & b 15 )
    ( string_push_char out hi )
    ( string_push_char out lo )
    = i + i 1
  }
  ^ out
}

// Returns 0..15, or -1 on non-hex byte.
@ __hex_value i c → i {
  ? & >= c 48 <= c 57  { ^ - c 48 } {}      // 0-9
  ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {} // a-f
  ? & >= c 65 <= c 70  { ^ + 10 - c 65 } {} // A-F
  ^ -1
}

@ hex_decode s str → ! String ParseErr {
  : i len ( nurl_str_len str )
  ? == len 0 { ^ @ ! String ParseErr { F @ ParseErr { Empty } } } {}
  ? != 0 & len 1 {
    ^ @ ! String ParseErr { F @ ParseErr { BadFormat } }
  } {}
  : String out ( string_with_cap / len 2 )
  : ~ i i 0
  ~ < i len {
    : i hi ( __hex_value ( nurl_str_get str i ) )
    : i lo ( __hex_value ( nurl_str_get str + i 1 ) )
    ? | < hi 0 < lo 0 {
      ( string_free out )
      ^ @ ! String ParseErr { F @ ParseErr { BadFormat } }
    } {}
    ( string_push_char out + lo * hi 16 )
    = i + i 2
  }
  ^ @ ! String ParseErr { T out }
}

// ── Base64 (RFC 4648) ───────────────────────────────────────────────

// Encode index n in 0..63 to its alphabet character. `url` selects the
// URL-safe alphabet (`-` and `_` for indices 62 and 63).
@ __b64_digit i n b url → i {
  ? < n 26 { ^ + 65 n } {}                   // 'A' + n
  ? < n 52 { ^ + 97 - n 26 } {}              // 'a' + (n-26)
  ? < n 62 { ^ + 48 - n 52 } {}              // '0' + (n-52)
  ? == n 62 {
    ? url { ^ 45 } {}                        // '-'
    ^ 43                                     // '+'
  } {}
  ? url { ^ 95 } {}                          // '_'
  ^ 47                                       // '/'
}

// Binary-safe emitter. Processes exactly n_in bytes from str.
@ __b64_emit String out s str i n_in b url b pad → v {
  : ~ i i 0
  : *u data # *u str
  ~ <= + i 3 n_in {
    : i b0 & 255 # i . data i
    : i b1 & 255 # i . data + i 1
    : i b2 & 255 # i . data + i 2
    : i n + + * b0 65536 * b1 256 b2
    ( string_push_char out ( __b64_digit & 63 / n 262144 url ) )
    ( string_push_char out ( __b64_digit & 63 / n 4096 url ) )
    ( string_push_char out ( __b64_digit & 63 / n 64 url ) )
    ( string_push_char out ( __b64_digit & 63 n url ) )
    = i + i 3
  }
  : i rem - n_in i
  ? == rem 1 {
    : i b0 & 255 # i . data i
    : i n  * b0 65536
    ( string_push_char out ( __b64_digit & 63 / n 262144 url ) )
    ( string_push_char out ( __b64_digit & 63 / n 4096 url ) )
    ? pad {
      ( string_push_char out 61 )  // '='
      ( string_push_char out 61 )
    } {}
  } {}
  ? == rem 2 {
    : i b0 & 255 # i . data i
    : i b1 & 255 # i . data + i 1
    : i n + * b0 65536 * b1 256
    ( string_push_char out ( __b64_digit & 63 / n 262144 url ) )
    ( string_push_char out ( __b64_digit & 63 / n 4096 url ) )
    ( string_push_char out ( __b64_digit & 63 / n 64 url ) )
    ? pad {
      ( string_push_char out 61 )  // '='
    } {}
  } {}
  ( __string_seal out )
}

@ b64_encode s str → String {
  : i len ( nurl_str_len str )
  ^ ( b64_encode_len str len )
}

@ b64_encode_len s str i len → String {
  : String out ( string_with_cap * 4 + 1 / len 3 )
  ( __b64_emit out str len F T )
  ^ out
}

@ b64_encode_vec ( Vec u ) v → String {
  : i len ( vec_len [u] v )
  : s data # s ( vec_data [u] v )
  ^ ( b64_encode_len data len )
}

@ b64_url_encode s str → String {
  : i len ( nurl_str_len str )
  : String out ( string_with_cap * 4 + 1 / len 3 )
  ( __b64_emit out str len T F )
  ^ out
}

// Returns 0..63, or -1 on non-alphabet byte. `url` selects the URL-safe
// alphabet (62 = '-', 63 = '_'). Padding `=` (61) returns -2.
@ __b64_value i c b url → i {
  ? & >= c 65 <= c 90  { ^ - c 65 } {}        // A-Z → 0..25
  ? & >= c 97 <= c 122 { ^ + 26 - c 97 } {}   // a-z → 26..51
  ? & >= c 48 <= c 57  { ^ + 52 - c 48 } {}   // 0-9 → 52..61
  ? url {
    ? == c 45 { ^ 62 } {}    // '-'
    ? == c 95 { ^ 63 } {}    // '_'
  } {
    ? == c 43 { ^ 62 } {}    // '+'
    ? == c 47 { ^ 63 } {}    // '/'
  }
  ? == c 61 { ^ -2 } {}      // '='
  ^ -1
}

// Internal decoder: ignores ASCII whitespace, fills `out` with bytes,
// returns ! v ParseErr. Active alphabet selected by `url`.
@ __b64_decode_into String out s str b url → ! v ParseErr {
  : i len ( nurl_str_len str )
  : ~ i pad 0
  : ~ i acc 0
  : ~ i nbits 0
  : ~ i i 0
  ~ < i len {
    : i c ( nurl_str_get str i )
    = i + i 1
    // Skip ASCII whitespace: space, tab, lf, cr, ff, vt
    ? | | | | | == c 32 == c 9 == c 10 == c 13 == c 12 == c 11 {} {
      : i v ( __b64_value c url )
      ? == v -2 {
        = pad + pad 1
        ? > pad 2 {
          ^ @ ! v ParseErr { F @ ParseErr { TrailingGarbage } }
        } {}
      } {
        ? > pad 0 {
          // Non-padding char after '=' is malformed.
          ^ @ ! v ParseErr { F @ ParseErr { TrailingGarbage } }
        } {}
        ? < v 0 {
          ^ @ ! v ParseErr { F @ ParseErr { BadFormat } }
        } {}
        = acc + * acc 64 v
        = nbits + nbits 6
        ? >= nbits 8 {
          = nbits - nbits 8
          // Bottom-of-byte alignment after consuming 6 bits at a time:
          // nbits is the residual count after this group (0..5). The
          // emitted byte is the top 8 bits of `acc`, so shift right by
          // `nbits` and mask.
          : i mask - << 1 nbits 1
          : i byte & 255 >> acc nbits
          ( string_push_char out byte )
          = acc & acc mask
        } {}
      }
    }
  }
  // Partial group with non-zero residual bits is malformed.
  ? > nbits 0 {
    ? != acc 0 {
      ^ @ ! v ParseErr { F @ ParseErr { BadFormat } }
    } {}
  } {}
  ^ @ ! v ParseErr { T 0 }
}

@ b64_decode s str → ! String ParseErr {
  : String out ( string_with_cap ( nurl_str_len str ) )
  : ! v ParseErr r ( __b64_decode_into out str F )
  ?? r {
    T _ → { ^ @ ! String ParseErr { T out } }
    F e → {
      ( string_free out )
      ^ @ ! String ParseErr { F e }
    }
  }
}

@ b64_url_decode s str → ! String ParseErr {
  : String out ( string_with_cap ( nurl_str_len str ) )
  : ! v ParseErr r ( __b64_decode_into out str T )
  ?? r {
    T _ → { ^ @ ! String ParseErr { T out } }
    F e → {
      ( string_free out )
      ^ @ ! String ParseErr { F e }
    }
  }
}
