// json_surrogate_lookahead.nu — the surrogate-pair LOOKAHEAD must be
// pure, and the parser must see the whole byte range.
//
// Six JSONTestSuite n_ cases parsed CLEAN before this test existed,
// from two roots:
//
//   * The low-surrogate lookahead consumed as it peeked. After
//     `\uD800`, a `\` was swallowed before knowing whether `u`
//     followed — so in `["\uD800\"]` the escape lost its backslash,
//     the stray quote closed the string, and a document whose string
//     NEVER terminates parsed successfully. And when `\u` did follow
//     with malformed hex (`\u`, `\u1`, `\u1x`, `\uDd"`), the
//     "best-effort" fallthrough dropped the error a plain `\uZZZZ`
//     would have raised. Now the lookahead consumes `\u` only after
//     both bytes matched, and once consumed the four digits MUST be
//     hex — the same rule every other escape lives by.
//
//   * `json_parse` takes `s`, so the document ends at the first NUL:
//     `123\0` TRUNCATED to `123` and parsed clean. The length-carrying
//     entries (`json_parse_n`, `json_parse_bytes`) never read past
//     their length, so the NUL is an ordinary rejected byte.
//
// A complete-but-unpaired surrogate stays ACCEPTED as U+FFFD (RFC 8259
// leaves it undefined; the replacement policy is pinned by
// json_rfc8259_strings), and the value that broke a pair re-enters the
// pairing loop, so a high surrogate followed by a real pair still
// decodes the real code point.
//
// Expected output:
//   surrogate then escaped quote rejected
//   surrogate then bare escape-u rejected
//   surrogate then 1-digit escape rejected
//   surrogate then bad hex rejected
//   incomplete low escape rejected
//   escape after replaced high accepted: EF BF BD 0A
//   high then real pair: EF BF BD F0 9D 84 9E
//   nul after number rejected: bad format
//   nul-free prefix still parses: 123

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`

@ show s label s src → v {
    ?? ( json_parse src ) {
        T j → {
            : String s2 ( json_stringify j )
            ( nurl_print label ) ( nurl_print `: ` )
            ( nurl_println ( string_data s2 ) )
            ( string_free s2 ) ( json_free j )
        }
        F e → {
            ( nurl_print label ) ( nurl_println ` rejected` )
        }
    }
}

// Parse and print the FIRST string element's bytes as hex.
@ show_hex s label s src → v {
    ?? ( json_parse src ) {
        T j → {
            ( nurl_print label ) ( nurl_print `: ` )
            : String hex ( string_new )
            ?? ( json_arr_get j 0 ) {
                T el → {
                    : s raw ( json_str_data el )
                    : s digits `0123456789ABCDEF`
                    : *u dp # *u digits
                    : i n ( nurl_str_len raw )
                    : ~ i k 0
                    ~ < k n {
                        ? > k 0 { ( string_push_char hex 32 ) } {}
                        : i b & 255 # i . # *u raw k
                        ( string_push_char hex # i . dp >> b 4 )
                        ( string_push_char hex # i . dp & b 15 )
                        = k + k 1
                    }
                }
                F → { ( string_push_str hex `no element` ) }
            }
            ( nurl_println ( string_data hex ) )
            ( string_free hex )
            ( json_free j )
        }
        F e → {
            ( nurl_print label ) ( nurl_println ` REJECTED` )
        }
    }
}

@ main → i {
    ( show `surrogate then escaped quote` `["\uD800\\"]` )
    ( show `surrogate then bare escape-u` `["\uD800\\u"]` )
    ( show `surrogate then 1-digit escape` `["\uD800\\u1"]` )
    ( show `surrogate then bad hex` `["\uD800\\u1x"]` )
    ( show `incomplete low escape` `["\uD834\\uDd"]` )
    ( show_hex `escape after replaced high accepted` `["\uD800\\n"]` )
    ( show_hex `high then real pair` `["\uD800𝄞"]` )
    : s withnul `123`
    : !Json JsonError rn ( json_parse_n withnul 4 )
    ?? rn {
        T j → { ( json_free j ) ( nurl_println `nul after number ACCEPTED` ) }
        F e → { ( nurl_println `nul after number rejected: bad format` ) }
    }
    : !Json JsonError rp ( json_parse_n withnul 3 )
    ?? rp {
        T j → {
            : String s2 ( json_stringify j )
            ( nurl_print `nul-free prefix still parses: ` )
            ( nurl_println ( string_data s2 ) )
            ( string_free s2 ) ( json_free j )
        }
        F e → { ( nurl_println `nul-free prefix REJECTED` ) }
    }
    ^ 0
}
