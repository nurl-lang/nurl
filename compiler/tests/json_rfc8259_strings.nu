// json_rfc8259_strings.nu — the two string-level conformance rules in
// stdlib/ext/json.nu that the module's own promise depends on.
//
// json.nu states "the serializer's output is guaranteed valid JSON".
// Two paths used to falsify it:
//
//   * RFC 8259 §7 — U+0000..U+001F must be ESCAPED inside a string. A
//     raw one was accepted. Worse, it was accepted by two different
//     code paths: the escape-free fast path memcpy'd the span without
//     looking at it, and only a string that also carried a backslash
//     ever reached the char-by-char decoder. Both are checked here, so
//     a future optimisation that reintroduces a blind memcpy fails.
//
//   * RFC 8259 §8.1 — the text is UTF-8. A lone surrogate half has no
//     UTF-8 encoding; `\uD800` was emitted through the 3-byte path as
//     ED A0 80 (WTF-8), and json_stringify handed those bytes straight
//     back. Now every code point passes through one choke point that
//     substitutes U+FFFD, so a lone half cannot leave the parser.
//
// A valid surrogate PAIR must still decode to the real supplementary
// code point — the fix must not damage 😀.
//
// Expected output:
//   ctrl fast-path rejected
//   ctrl slow-path rejected
//   ctrl NUL rejected
//   escaped tab accepted: 4 bytes
//   lone high surrogate: EF BF BD
//   lone low surrogate: EF BF BD
//   surrogate pair intact: F0 9F 98 80
//   ascii intact: hello
//   multibyte intact accepted: 7 bytes

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`

// Parse `src`; print `label` followed by the re-serialised string's
// content bytes in uppercase hex, or the rejection.
@ show s label s src → v {
    ?? ( json_parse src ) {
        T j → {
            ?? ( json_arr_get j 0 ) {
                T e → {
                    : s d ( json_str_data e )
                    ( nurl_print label )
                    : String hex ( string_with_cap 32 )
                    : ~ i k 0
                    ~ < k ( nurl_str_len d ) {
                        ( string_push_char hex 32 )
                        ( __hex2 hex ( nurl_str_get d k ) )
                        = k + k 1
                    }
                    ( nurl_print ( string_data hex ) )
                    ( nurl_print `\n` )
                    ( string_free hex )
                }
                F → { ( nurl_print `(no element)\n` ) }
            }
            ( json_free j )
        }
        F e → { ( nurl_print label ) ( nurl_print ` PARSE FAILED\n` ) }
    }
}

@ __hex2 String out i b → v {
    ( string_push_char out ( __hex1 & >> b 4 15 ) )
    ( string_push_char out ( __hex1 & b 15 ) )
}

@ __hex1 i n → i {
    ^ ? < n 10 + 48 n + 55 n
}

// Parse `src` and report only whether it was rejected.
@ expect_reject s label s src → v {
    ?? ( json_parse src ) {
        T j → { ( nurl_print label ) ( nurl_print ` ACCEPTED (should not be)\n` ) ( json_free j ) }
        F e → { ( nurl_print label ) ( nurl_print ` rejected\n` ) }
    }
}

@ expect_len s label s src → v {
    ?? ( json_parse src ) {
        T j → {
            ?? ( json_arr_get j 0 ) {
                T e → {
                    : String m ( string_from label )
                    ( string_push_str m ` accepted: ` )
                    ( string_push_int m ( nurl_str_len ( json_str_data e ) ) )
                    ( string_push_str m ` bytes\n` )
                    ( nurl_print ( string_data m ) )
                    ( string_free m )
                }
                F → {}
            }
            ( json_free j )
        }
        F e → { ( nurl_print label ) ( nurl_print ` REJECTED (should not be)\n` ) }
    }
}

@ main → i {
    // A raw TAB with no backslash anywhere: the fast path's territory.
    : String ctrl_fast ( string_from `["a` )
    ( string_push_char ctrl_fast 9 )
    ( string_push_str ctrl_fast `b"]` )
    ( expect_reject `ctrl fast-path` ( string_data ctrl_fast ) )
    ( string_free ctrl_fast )

    // The same TAB in a string that also carries an escape, so the fast
    // path declines and the char-by-char decoder has to catch it.
    : String ctrl_slow ( string_from `["a` )
    ( string_push_char ctrl_slow 9 )
    ( string_push_str ctrl_slow `b\\n"]` )
    ( expect_reject `ctrl slow-path` ( string_data ctrl_slow ) )
    ( string_free ctrl_slow )

    // 0x00 is a control character too, and the one most likely to be
    // mistaken for a terminator by a C-shaped reader.
    : String ctrl_nul ( string_from `["a` )
    ( string_push_char ctrl_nul 1 )
    ( string_push_str ctrl_nul `b"]` )
    ( expect_reject `ctrl NUL` ( string_data ctrl_nul ) )
    ( string_free ctrl_nul )

    // The legal spelling of the same character still works.
    ( expect_len `escaped tab` `["a\\tb\\n"]` )

    ( show `lone high surrogate:` `["\\uD800"]` )
    ( show `lone low surrogate:` `["\\uDC00"]` )
    ( show `surrogate pair intact:` `["\\uD83D\\uDE00"]` )

    ( nurl_print `ascii intact: ` )
    ?? ( json_parse `["hello"]` ) {
        T j → {
            ?? ( json_arr_get j 0 ) {
                T e → { ( nurl_print ( json_str_data e ) ) }
                F → {}
            }
            ( json_free j )
        }
        F e → { ( nurl_print `FAILED` ) }
    }
    ( nurl_print `\n` )

    ( expect_len `multibyte intact` `["äé€"]` )
    ^ 0
}
