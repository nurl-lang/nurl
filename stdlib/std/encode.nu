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
//   ( b32_encode s )           → String              standard alphabet, padded
//   ( b32_encode_len s i )     → String              binary-safe (NUL ok)
//   ( b32_encode_vec (Vec u) ) → String              binary-safe
//   ( b32_decode s )           → ! String ParseErr   standard, padding optional,
//                                                     case-insensitive (TOTP)

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
    ? > len 0 {
        : *u src # *u str
        // Exactly 2 output bytes per input byte — reserve once and write
        // through the cursor (string_push_char is ~12x the cost here).
        : *u w ( string_reserve_at out * len 2 )
        : ~ i i 0
        ~ < i len {
            : i b & # i . src i 255
            = . w * i 2 # u ( __hex_digit & 15 / b 16 )
            = . w + * i 2 1 # u ( __hex_digit & b 15 )
            = i + i 1
        }
        ( string_commit out * len 2 )
    } {}
    ^ out
}

// Returns 0..15, or -1 on non-hex byte.
@ __hex_value i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}  // 0-9
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}  // a-f
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}  // A-F
    ^ -1
}

@ hex_decode s str → !String ParseErr {
    : i len ( nurl_str_len str )
    ? == len 0 { ^ @ !String ParseErr { F @ ParseErr { Empty } } } {}
    ? != 0 & len 1 {
        ^ @ !String ParseErr { F @ ParseErr { BadFormat } }
    } {}
    : String out ( string_with_cap / len 2 )
    : ~ i i 0
    ~ < i len {
        : i hi ( __hex_value ( nurl_str_at str len i ) )
        : i lo ( __hex_value ( nurl_str_at str len + i 1 ) )
        ? | < hi 0 < lo 0 {
            ( string_free out )
            ^ @ !String ParseErr { F @ ParseErr { BadFormat } }
        } {}
        ( string_push_char out + lo * hi 16 )
        = i + i 2
    }
    ^ @ !String ParseErr { T out }
}

// ── Base64 (RFC 4648) ───────────────────────────────────────────────

// Encode index n in 0..63 to its alphabet character. `url` selects the
// URL-safe alphabet (`-` and `_` for indices 62 and 63).
@ __b64_digit i n b url → i {
    ? < n 26 { ^ + 65 n } {}  // 'A' + n
    ? < n 52 { ^ + 97 - n 26 } {}  // 'a' + (n-26)
    ? < n 62 { ^ + 48 - n 52 } {}  // '0' + (n-52)
    ? == n 62 {
        ? url { ^ 45 } {}  // '-'
        ^ 43  // '+'
    } {}
    ? url { ^ 95 } {}  // '_'
    ^ 47  // '/'
}

// Binary-safe emitter. Processes exactly n_in bytes from str.
//
// The output length is a pure function of n_in, so the whole result is
// reserved once and written through a raw cursor. The previous version
// paid a `string_push_char` per output character — a call plus three
// control-block reads each — which dominated base64 entirely (measured
// 3.8 ns per input byte).
@ __b64_emit String out s str i n_in b url b pad → v {
    ? <= n_in 0 { ^ } {}
    : i groups / n_in 3
    : i rem_in - n_in * groups 3
    : i tail ? == rem_in 0 0 ? pad 4 ? == rem_in 1 2 3
    : i out_n + * groups 4 tail
    : *u data # *u str
    : *u w ( string_reserve_at out out_n )
    : ~ i i 0
    : ~ i o 0
    ~ <= + i 3 n_in {
        : i b0 & 255 # i . data i
        : i b1 & 255 # i . data + i 1
        : i b2 & 255 # i . data + i 2
        : i n + + * b0 65536 * b1 256 b2
        = . w o # u ( __b64_digit & 63 / n 262144 url )
        = . w + o 1 # u ( __b64_digit & 63 / n 4096 url )
        = . w + o 2 # u ( __b64_digit & 63 / n 64 url )
        = . w + o 3 # u ( __b64_digit & 63 n url )
        = i + i 3
        = o + o 4
    }
    : i rem - n_in i
    ? == rem 1 {
        : i b0 & 255 # i . data i
        : i n * b0 65536
        = . w o # u ( __b64_digit & 63 / n 262144 url )
        = . w + o 1 # u ( __b64_digit & 63 / n 4096 url )
        = o + o 2
        ? pad {
            : u eq # u 61  // '='
            = . w o eq
            = . w + o 1 eq
            = o + o 2
        } {}
    } {}
    ? == rem 2 {
        : i b0 & 255 # i . data i
        : i b1 & 255 # i . data + i 1
        : i n + * b0 65536 * b1 256
        = . w o # u ( __b64_digit & 63 / n 262144 url )
        = . w + o 1 # u ( __b64_digit & 63 / n 4096 url )
        = . w + o 2 # u ( __b64_digit & 63 / n 64 url )
        = o + o 3
        ? pad {
            = . w o # u 61  // '='
            = o + o 1
        } {}
    } {}
    ( string_commit out o )
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

// URL-safe, UN-padded base64 over a binary Vec[u]. Unlike
// `b64_url_encode`, the length comes from `vec_len`, not `strlen`, so
// material with embedded 0x00 bytes (a raw HMAC tag or Ed25519
// signature — exactly what JWT base64url-encodes) is encoded whole.
// `__b64_emit` reads through a `*u` pointer, so the binary input is
// never truncated.
@ b64_url_encode_vec ( Vec u ) v → String {
    : i len ( vec_len [u] v )
    : s data # s ( vec_data [u] v )
    : String out ( string_with_cap * 4 + 1 / len 3 )
    ( __b64_emit out data len T F )
    ^ out
}

// URL-safe base64 decode to a binary Vec[u] (tolerates missing padding,
// as JWT segments are unpadded). The decoded bytes may contain 0x00, so
// the result is a Vec, not a String — read it with the `. p k` indexed
// load, never nurl_str_get.
// Standard base64 → owned byte vector. Unlike `b64_decode` (which yields
// a String) this is NUL-safe: the decoded bytes may contain any value,
// including 0, so callers that need raw binary (crypto salts, signatures,
// the SCRAM wire) must use this rather than reading through a String.
@ b64_decode_vec s str → !( Vec u ) ParseErr {
    : !String ParseErr r ( b64_decode str )
    ?? r {
        T sv → {
            : i n ( string_len sv )
            : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
            ? > n 0 {
                ( nurl_memcpy ( vec_data [u] v ) # *u ( string_data sv ) n )
                : b _ok ( vec_set_len [u] v n )
            } {}
            ( string_free sv )
            ^ @ !( Vec u ) ParseErr { T v }
        }
        F e → { ^ @ !( Vec u ) ParseErr { F e } }
    }
}

@ b64_url_decode_vec s str → !( Vec u ) ParseErr {
    : !String ParseErr r ( b64_url_decode str )
    ?? r {
        T sv → {
            : i n ( string_len sv )
            : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
            ? > n 0 {
                ( nurl_memcpy ( vec_data [u] v ) # *u ( string_data sv ) n )
                : b _ok ( vec_set_len [u] v n )
            } {}
            ( string_free sv )
            ^ @ !( Vec u ) ParseErr { T v }
        }
        F e → { ^ @ !( Vec u ) ParseErr { F e } }
    }
}

// Returns 0..63, or -1 on non-alphabet byte. `url` selects the URL-safe
// alphabet (62 = '-', 63 = '_'). Padding `=` (61) returns -2.
@ __b64_value i c b url → i {
    ? & >= c 65 <= c 90 { ^ - c 65 } {}  // A-Z → 0..25
    ? & >= c 97 <= c 122 { ^ + 26 - c 97 } {}  // a-z → 26..51
    ? & >= c 48 <= c 57 { ^ + 52 - c 48 } {}  // 0-9 → 52..61
    ? url {
        ? == c 45 { ^ 62 } {}  // '-'
        ? == c 95 { ^ 63 } {}  // '_'
    } {
        ? == c 43 { ^ 62 } {}  // '+'
        ? == c 47 { ^ 63 } {}  // '/'
    }
    ? == c 61 { ^ -2 } {}  // '='
    ^ -1
}

// Internal decoder: ignores ASCII whitespace, fills `out` with bytes,
// returns ! v ParseErr. Active alphabet selected by `url`.
@ __b64_decode_into String out s str b url → !v ParseErr {
    : i len ( nurl_str_len str )
    // Read through a raw pointer: nurl_str_get re-runs strlen on every
    // call, which turns this loop quadratic on big inputs (a 300 KB
    // charsmap blob took seconds).
    : *u P # *u str
    : ~ i pad 0
    : ~ i acc 0
    : ~ i nbits 0
    : ~ i i 0
    ~ < i len {
        : i c & 255 # i . P i
        = i + i 1
        // Skip ASCII whitespace: space, tab, lf, cr, ff, vt
        ? | | | | | == c 32 == c 9 == c 10 == c 13 == c 12 == c 11 {} {
            : i v ( __b64_value c url )
            ? == v -2 {
                = pad + pad 1
                ? > pad 2 {
                    ^ @ !v ParseErr { F @ ParseErr { TrailingGarbage } }
                } {}
            } {
                ? > pad 0 {
                    // Non-padding char after '=' is malformed.
                    ^ @ !v ParseErr { F @ ParseErr { TrailingGarbage } }
                } {}
                ? < v 0 {
                    ^ @ !v ParseErr { F @ ParseErr { BadFormat } }
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
            ^ @ !v ParseErr { F @ ParseErr { BadFormat } }
        } {}
    } {}
    ^ @ !v ParseErr { T 0 }
}

@ b64_decode s str → !String ParseErr {
    : String out ( string_with_cap ( nurl_str_len str ) )
    : !v ParseErr r ( __b64_decode_into out str F )
    ?? r {
        T _ → { ^ @ !String ParseErr { T out } }
        F e → {
            ( string_free out )
            ^ @ !String ParseErr { F e }
        }
    }
}

@ b64_url_decode s str → !String ParseErr {
    : String out ( string_with_cap ( nurl_str_len str ) )
    : !v ParseErr r ( __b64_decode_into out str T )
    ?? r {
        T _ → { ^ @ !String ParseErr { T out } }
        F e → {
            ( string_free out )
            ^ @ !String ParseErr { F e }
        }
    }
}

// ── Base32 (RFC 4648) ───────────────────────────────────────────────
//
// Standard alphabet `A-Z2-7`, padded with `=` to an 8-char boundary.
// This is the alphabet RFC 6238 TOTP secrets use. The decoder is
// case-insensitive, ignores ASCII whitespace, and treats padding as
// optional, so a bare uppercase TOTP secret decodes without massaging.

// Encode index n in 0..31 to its alphabet character.
@ __b32_digit i n → i {
    ? < n 26 { ^ + 65 n } {}  // 'A' + n
    ^ + 50 - n 26  // '2' + (n-26)
}

// Binary-safe emitter. Processes exactly n_in bytes from str, packing
// 5 bits per output char via an MSB-first bit accumulator. Trailing
// bits are zero-padded up to the final 5-bit group; `pad` then appends
// `=` to the next 8-char boundary (count fixed by n_in mod 5).
@ __b32_emit String out s str i n_in b pad → v {
    : *u data # *u str
    : ~ i acc 0
    : ~ i nbits 0
    : ~ i i 0
    ~ < i n_in {
        : i bb & 255 # i . data i
        = acc + * acc 256 bb
        = nbits + nbits 8
        = i + i 1
        ~ >= nbits 5 {
            = nbits - nbits 5
            ( string_push_char out ( __b32_digit & 31 >> acc nbits ) )
            : i mask - << 1 nbits 1
            = acc & acc mask
        }
    }
    ? > nbits 0 {
        // Left-justify the residual bits into a final 5-bit group.
        ( string_push_char out ( __b32_digit & 31 << acc - 5 nbits ) )
    } {}
    ? pad {
        : i rem % n_in 5
        : ~ i padn 0
        ? == rem 1 { = padn 6 } {}
        ? == rem 2 { = padn 4 } {}
        ? == rem 3 { = padn 3 } {}
        ? == rem 4 { = padn 1 } {}
        : ~ i p 0
        ~ < p padn {
            ( string_push_char out 61 )  // '='
            = p + p 1
        }
    } {}
    ( _string_seal out )
}

@ b32_encode s str → String {
    : i len ( nurl_str_len str )
    ^ ( b32_encode_len str len )
}

@ b32_encode_len s str i len → String {
    : String out ( string_with_cap * 8 + 1 / len 5 )
    ( __b32_emit out str len T )
    ^ out
}

@ b32_encode_vec ( Vec u ) v → String {
    : i len ( vec_len [u] v )
    : s data # s ( vec_data [u] v )
    ^ ( b32_encode_len data len )
}

// Returns 0..31, or -1 on non-alphabet byte. Padding `=` (61) returns
// -2. Both letter cases map to the same value (case-insensitive).
@ __b32_value i c → i {
    ? & >= c 65 <= c 90 { ^ - c 65 } {}  // A-Z → 0..25
    ? & >= c 97 <= c 122 { ^ - c 97 } {}  // a-z → 0..25
    ? & >= c 50 <= c 55 { ^ + 26 - c 50 } {}  // '2'-'7' → 26..31
    ? == c 61 { ^ -2 } {}  // '='
    ^ -1
}

// Internal decoder: ignores ASCII whitespace, fills `out` with bytes,
// returns ! v ParseErr.
@ __b32_decode_into String out s str → !v ParseErr {
    : i len ( nurl_str_len str )
    : ~ i pad 0
    : ~ i acc 0
    : ~ i nbits 0
    : ~ i i 0
    ~ < i len {
        : i c ( nurl_str_at str len i )
        = i + i 1
        // Skip ASCII whitespace: space, tab, lf, cr, ff, vt
        ? | | | | | == c 32 == c 9 == c 10 == c 13 == c 12 == c 11 {} {
            : i v ( __b32_value c )
            ? == v -2 {
                = pad + pad 1
                ? > pad 6 {
                    ^ @ !v ParseErr { F @ ParseErr { TrailingGarbage } }
                } {}
            } {
                ? > pad 0 {
                    // Non-padding char after '=' is malformed.
                    ^ @ !v ParseErr { F @ ParseErr { TrailingGarbage } }
                } {}
                ? < v 0 {
                    ^ @ !v ParseErr { F @ ParseErr { BadFormat } }
                } {}
                = acc + * acc 32 v
                = nbits + nbits 5
                ? >= nbits 8 {
                    = nbits - nbits 8
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
            ^ @ !v ParseErr { F @ ParseErr { BadFormat } }
        } {}
    } {}
    ^ @ !v ParseErr { T 0 }
}

@ b32_decode s str → !String ParseErr {
    : String out ( string_with_cap ( nurl_str_len str ) )
    : !v ParseErr r ( __b32_decode_into out str )
    ?? r {
        T _ → { ^ @ !String ParseErr { T out } }
        F e → {
            ( string_free out )
            ^ @ !String ParseErr { F e }
        }
    }
}
