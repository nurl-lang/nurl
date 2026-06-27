// stdlib/std/utf8.nu — a UTF-8 codepoint layer over NURL's byte strings.
//
// NURL's `s` is a byte string (UTF-8 in, UTF-8 out) and `core/string.nu`
// indexes, slices and reverses at the BYTE level — fast, but it splits a
// multi-byte character silently. This module adds the codepoint layer:
// a validating decoder (rejects overlong forms, UTF-16 surrogates, and
// out-of-range scalars), codepoint counting and indexing, an encoder, and
// codepoint-aware substring / reverse that never cut a character in half.
//
// Bytes are read via `nurl_str_get`, which already masks to 0..255, so the
// high bytes of a multi-byte sequence arrive unsigned.
//
// Design: the decoder is total. On malformed input it yields the Unicode
// replacement scalar U+FFFD with width 1 and ok=0, so a caller may either
// stop (check `ok`) or resynchronise one byte at a time without looping.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: i UTF8_REPLACEMENT 65533  // U+FFFD
: i UTF8_MAX 1114111  // U+10FFFF, the largest legal scalar

// One decode step: the scalar value, the number of bytes it consumed, and
// whether the bytes were a well-formed encoding (ok = 1) or a recovered
// error (ok = 0, cp = U+FFFD, width = 1). At end-of-string width = 0.
: Utf8Dec { i cp i width i ok }

// A continuation byte is 10xxxxxx.
@ __utf8_is_cont i b → b {
    ^ & >= b 128 < b 192
}

// Decode the scalar starting at byte offset `pos`. `pos` must be a code-
// point boundary; if it lands inside a sequence the byte is reported as a
// 1-byte error so the caller can resynchronise.
@ utf8_decode s str i pos → Utf8Dec {
    : i n ( nurl_str_len str )
    ? >= pos n { ^ @ Utf8Dec { 0 0 0 } } {}  // end of string
    : i b0 ( nurl_str_get str pos )

    // 1-byte: 0xxxxxxx
    ? < b0 128 { ^ @ Utf8Dec { b0 1 1 } } {}
    // stray continuation byte 10xxxxxx — not a leader
    ? < b0 192 { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}

    // 2-byte: 110xxxxx 10xxxxxx
    ? < b0 224 {
        ? >= + pos 1 n { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i b1 ( nurl_str_get str + pos 1 )
        ? ! ( __utf8_is_cont b1 ) { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i cp | << & b0 31 6 & b1 63
        ? < cp 128 { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}  // overlong
        ^ @ Utf8Dec { cp 2 1 }
    } {}

    // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
    ? < b0 240 {
        ? >= + pos 2 n { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i b1 ( nurl_str_get str + pos 1 )
        : i b2 ( nurl_str_get str + pos 2 )
        ? | ! ( __utf8_is_cont b1 ) ! ( __utf8_is_cont b2 )
        { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i cp | | << & b0 15 12 << & b1 63 6 & b2 63
        ? < cp 2048 { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}  // overlong
        ? & >= cp 55296 <= cp 57343  // UTF-16 surrogate
        { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        ^ @ Utf8Dec { cp 3 1 }
    } {}

    // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    ? < b0 248 {
        ? >= + pos 3 n { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i b1 ( nurl_str_get str + pos 1 )
        : i b2 ( nurl_str_get str + pos 2 )
        : i b3 ( nurl_str_get str + pos 3 )
        ? | | ! ( __utf8_is_cont b1 ) ! ( __utf8_is_cont b2 ) ! ( __utf8_is_cont b3 )
        { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}
        : i cp | | | << & b0 7 18 << & b1 63 12 << & b2 63 6 & b3 63
        ? < cp 65536 { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}  // overlong
        ? > cp UTF8_MAX { ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 } } {}  // out of range
        ^ @ Utf8Dec { cp 4 1 }
    } {}

    // 0xF8..0xFF are never valid leaders.
    ^ @ Utf8Dec { UTF8_REPLACEMENT 1 0 }
}

// True iff `str` is well-formed UTF-8 end to end.
@ utf8_valid s str → b {
    : i n ( nurl_str_len str )
    : ~ i pos 0
    : ~ b ok T
    ~ & < pos n ok {
        : Utf8Dec d ( utf8_decode str pos )
        ? == . d ok 0 { = ok F } { = pos + pos . d width }
    }
    ^ ok
}

// Number of scalars in a valid string; -1 if the string is not valid UTF-8.
@ utf8_len s str → i {
    : i n ( nurl_str_len str )
    : ~ i pos 0
    : ~ i count 0
    ~ < pos n {
        : Utf8Dec d ( utf8_decode str pos )
        ? == . d ok 0 { ^ -1 } {}
        = count + count 1
        = pos + pos . d width
    }
    ^ count
}

// Byte offset of the `n`-th scalar (0-based). `n` == scalar-count returns the
// byte length (one past the end); -1 if `n` is larger, or the string is
// malformed before reaching it.
@ utf8_byte_offset s str i n → i {
    ? < n 0 { ^ -1 } {}
    : i blen ( nurl_str_len str )
    : ~ i pos 0
    : ~ i k 0
    ~ < k n {
        ? >= pos blen { ^ -1 } {}
        : Utf8Dec d ( utf8_decode str pos )
        ? == . d ok 0 { ^ -1 } {}
        = pos + pos . d width
        = k + k 1
    }
    ^ pos
}

// The `n`-th scalar (0-based codepoint index), or None if out of range or the
// string is malformed at or before it.
@ utf8_nth s str i n → ?i {
    : i off ( utf8_byte_offset str n )
    ? < off 0 { ^ @ ?i { F 0 } } {}
    : i blen ( nurl_str_len str )
    ? >= off blen { ^ @ ?i { F 0 } } {}
    : Utf8Dec d ( utf8_decode str off )
    ? == . d ok 0 { ^ @ ?i { F 0 } } {}
    ^ @ ?i { T . d cp }
}

// Append scalar `cp` to `out` as 1..4 UTF-8 bytes. An out-of-range or
// surrogate scalar is encoded as U+FFFD rather than producing invalid bytes.
@ utf8_push_cp String out i cp → v {
    : ~ i c cp
    ? | < c 0 | > c UTF8_MAX & >= c 55296 <= c 57343 { = c UTF8_REPLACEMENT } {}
    ? < c 128 {
        ( string_push_char out c )
    } {
        ? < c 2048 {
            ( string_push_char out | 192 >> c 6 )
            ( string_push_char out | 128 & c 63 )
        } {
            ? < c 65536 {
                ( string_push_char out | 224 >> c 12 )
                ( string_push_char out | 128 & >> c 6 63 )
                ( string_push_char out | 128 & c 63 )
            } {
                ( string_push_char out | 240 >> c 18 )
                ( string_push_char out | 128 & >> c 12 63 )
                ( string_push_char out | 128 & >> c 6 63 )
                ( string_push_char out | 128 & c 63 )
            }
        }
    }
}

// Encode a single scalar to a fresh String.
@ utf8_encode_cp i cp → String {
    : String out ( string_with_cap 4 )
    ( utf8_push_cp out cp )
    ^ out
}

// All scalars of `str` as a Vec[i]. Malformed bytes decode to U+FFFD, so the
// result is always a usable scalar sequence (use `utf8_valid` to reject).
@ utf8_codepoints s str → ( Vec i ) {
    : i n ( nurl_str_len str )
    : ( Vec i ) out ( vec_new [i] )
    : ~ i pos 0
    ~ < pos n {
        : Utf8Dec d ( utf8_decode str pos )
        ( vec_push [i] out . d cp )
        = pos + pos ? > . d width 0 . d width 1
    }
    ^ out
}

// Build a String from a Vec[i] of scalars.
@ utf8_from_codepoints ( Vec i ) cps → String {
    : i n ( vec_len [i] cps )
    : String out ( string_with_cap * n 2 )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [i] cps i ) {
            T cp → { ( utf8_push_cp out cp ) }
            F _ → {}
        }
        = i + i 1
    }
    ^ out
}

// Codepoint-aware substring: up to `count` scalars starting at scalar `from`.
// Clamps to the string's bounds; never splits a multi-byte character.
@ utf8_substr s str i from i count → String {
    : i start ( utf8_byte_offset str from )
    ? | < start 0 < count 0 { ^ ( string_with_cap 0 ) } {}
    : i blen ( nurl_str_len str )
    : ~ i pos start
    : ~ i k 0
    : String out ( string_with_cap 16 )
    ~ & < k count < pos blen {
        : Utf8Dec d ( utf8_decode str pos )
        : i w ? > . d width 0 . d width 1
        : ~ i j 0
        ~ < j w {
            ( string_push_char out ( nurl_str_get str + pos j ) )
            = j + j 1
        }
        = pos + pos w
        = k + k 1
    }
    ^ out
}

// Codepoint-aware reverse — reverses whole scalars, preserving every
// multi-byte character (unlike `string_reverse`, which reverses bytes).
@ utf8_reverse s str → String {
    : ( Vec i ) cps ( utf8_codepoints str )
    : i n ( vec_len [i] cps )
    : String out ( string_with_cap * n 2 )
    : ~ i i - n 1
    ~ >= i 0 {
        ?? ( vec_get [i] cps i ) {
            T cp → { ( utf8_push_cp out cp ) }
            F _ → {}
        }
        = i - i 1
    }
    ( vec_free [i] cps )
    ^ out
}
