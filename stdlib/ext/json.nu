// stdlib/ext/json.nu — recursive-descent JSON parser, serializer, accessors
//
// JSON is the lingua franca of LLM tool-use payloads. This module provides
// a single canonical Json value type, a strict parser that rejects malformed
// input via `! Json JsonError`, a compact serializer that round-trips, and
// a small set of accessors so call sites don't have to ?? match for every
// field probe.
//
// ── Json value ──────────────────────────────────────────────────────
//
//   : | Json {
//     JNull
//     JBool b
//     JNum  String      // raw textual digits (no precision loss either way)
//     JStr  String      // unescaped UTF-8 content
//     JArr  ( Vec Json )
//     JObj  ( Vec Json ) // alternating: even idx = JStr key, odd = value
//   }
//
// JNum stores the original textual form (`-3.14`, `42`, `1e10`, …). Use
// `json_num_as_i` / `json_num_as_f` to project to numeric types when
// needed; this avoids forcing every JSON int to lose information through
// double rounding and keeps the serializer trivial. The parser rejects
// non-conforming numbers (RFC 8259: leading zeros like `01` → BadFormat),
// so the serializer's output is guaranteed valid JSON.
//
// JObj is a Vec of alternating key-value entries. Keys are JStr (always),
// values can be any Json. Lookup is O(n) — fine for LLM-typical payloads
// (tens of fields). If you need O(1) probe, copy into a HashMap[s i] or
// similar — left to the caller. Duplicate keys are preserved as-is by
// the parser (the JSON spec allows but does not mandate handling); the
// accessor `json_obj_get` returns the first match in source order, and
// `json_obj_set` replaces the first match in source order.
//
// ── Errors ──────────────────────────────────────────────────────────
//
//   : JsonError {
//     ParseErr kind   // BadFormat / Empty / TrailingGarbage / Overflow
//     i pos           // 0-based byte offset of the failure (or token start)
//     i line          // 1-based line number
//     i col           // 1-based column
//   }
//
// Location is computed once per failure and travels with the error value
// — there is no global state, so nested `json_parse` calls (e.g. an error
// handler that parses a fallback config) and multi-threaded use are both
// safe. Render with `json_format_error` or build your own message.
//
// ── API ─────────────────────────────────────────────────────────────
//
// Constructors:
//   ( json_null )                     → Json
//   ( json_bool   v )                 → Json
//   ( json_num_lit raw )              → Json    raw as i8* (gets copied)
//   ( json_str_lit raw )              → Json    raw as i8* (gets copied)
//   ( json_int  n )                   → Json    JNum from primitive int
//   ( json_float x )                  → Json    JNum from primitive float
//   ( json_arr_new )                  → Json    empty []
//   ( json_obj_new )                  → Json    empty {}
//   ( json_arr v )                    → Json    takes ownership of Vec
//   ( json_obj v )                    → Json    takes ownership of Vec
//
// Predicates / typing:
//   ( json_is_null j ) / _bool / _num / _str / _arr / _obj  → b
//   ( json_type_name j )              → s    "null"/"bool"/"num"/"str"/"arr"/"obj"
//
// Parser / serializer:
//   ( json_parse raw )                → ! Json JsonError
//   ( json_stringify j )              → String  compact (always valid JSON)
//   ( json_pretty    j )              → String  2-space indented
//   ( json_format_error e )           → String  "<kind> at line L col C" (caller owns)
//
// Iteration:
//   ( json_arr_each  j f )            → v    f : (@ v Json)
//   ( json_obj_each  j f )            → v    f : (@ v s Json) (raw key, value)
//   ( json_obj_keys  j )              → ( Vec String )  fresh owned copies
//
// Containers — random access (return None / 0 on miss or wrong variant):
//   ( json_arr_len   j )              → i
//   ( json_arr_get   j idx )          → ? Json   borrowed
//   ( json_obj_get   j key_raw )      → ? Json   borrowed; first match in order
//   ( json_obj_has   j key_raw )      → b
//   ( json_get       j dotted_path )  → ? Json   borrowed; see "Path access"
//
// Leaf accessors:
//   ( json_num_as_i  j )              → ? i    parses JNum; None on overflow/non-int
//   ( json_num_as_f  j )              → ? f    parses JNum; None on parse fail
//   ( json_str_data  j )              → s      borrowed; "" on wrong variant
//   ( json_bool_val  j )              → b      F on wrong variant
//   ( json_as_str    j )              → s      alias of json_str_data
//   ( json_as_int    j )              → i      lenient: JNum→int, JBool→1/0, else 0
//   ( json_as_bool   j )              → b      strict JBool unwrap (F on miss)
//
// Mutation (build-style — consume the supplied element/value on success):
//   ( json_arr_push  j elem )         → b      F if j is not an array
//   ( json_obj_set   j key_raw val )  → b      F if j is not an object;
//                                              replaces first match in order
//
// Copy / compare / free:
//   ( json_clone j )                  → Json   deep copy, caller owns
//   ( json_eq    a b )                → b      byte-exact JNum, order-sensitive JObj
//   ( json_free  j )                  → v      recursive
//
// Errors: `ParseErr` from stdlib/core/errors.nu, wrapped in `JsonError`:
//   Empty           — no value found (whitespace / EOF before any value)
//   BadFormat       — anything malformed at the byte level (incl. leading
//                     zeros like `01`, which RFC 8259 forbids)
//   TrailingGarbage — well-formed value followed by non-whitespace junk
//   Overflow        — nesting depth exceeded `JSON_MAX_DEPTH`
//
// Notes / limits:
//   - Max nesting depth is `JSON_MAX_DEPTH` (1024) — guards against
//     stack-blowing payloads like `[[[[[[…]]]]]]`.
//   - `json_get` paths split on `.`. A purely-numeric segment ALWAYS
//     means array index — there is no escape syntax to reach a numeric
//     key in an object via path; use `json_obj_get` directly for those.
//   - Duplicate object keys are preserved; first-match wins for lookup.
//     If you need set semantics, project into a HashMap.

$ `stdlib/core/errors.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// memchr — glibc's SIMD-vectorised byte search. Used in
// `__jp_parse_string`'s fast path to find the closing quote and (in
// the same direction) the first backslash, replacing a byte-by-byte
// NURL loop. Returns NULL when the byte is not present in [buf, buf+n).
& `c` @ memchr s buf i c i n → s

: | Json {
    JNull
    JBool b
    JNum String
    JStr String
    JArr ( Vec Json )
    JObj ( Vec Json )
}

: JsonError {
    ParseErr kind
    i pos
    i line
    i col
}

// ── Constructors ─────────────────────────────────────────────────────

@ json_null → Json {
    ^ @ Json { JNull }
}

@ json_bool b v → Json {
    ^ @ Json { JBool v }
}

@ json_num_lit s raw → Json {
    ^ @ Json { JNum ( string_from raw ) }
}

@ json_str_lit s raw → Json {
    ^ @ Json { JStr ( string_from raw ) }
}

// Numeric convenience: build a JNum from a primitive int / float. The
// raw text uses the canonical decimal form (matches `nurl_str_int`).
@ json_int i n → Json {
    : String s ( string_with_cap 16 )
    ( string_push_int s n )
    ^ @ Json { JNum s }
}

@ json_float f x → Json {
    : s raw ( nurl_str_float x )
    : String s ( string_from raw )
    ^ @ Json { JNum s }
}

// Empty array / object — shorter than `( json_arr ( vec_new [Json] ) )`.
@ json_arr_new → Json {
    : ( Vec Json ) v ( vec_new [Json] )
    ^ @ Json { JArr v }
}

@ json_obj_new → Json {
    : ( Vec Json ) v ( vec_new [Json] )
    ^ @ Json { JObj v }
}

@ json_arr ( Vec Json ) v → Json {
    ^ @ Json { JArr v }
}

@ json_obj ( Vec Json ) v → Json {
    ^ @ Json { JObj v }
}

// ── Predicates ───────────────────────────────────────────────────────

@ json_is_null Json j → b {
    ^ ?? j { JNull → T _ → F }
}

@ json_is_bool Json j → b {
    ^ ?? j { JBool _ → T _ → F }
}

@ json_is_num Json j → b {
    ^ ?? j { JNum _ → T _ → F }
}

@ json_is_str Json j → b {
    ^ ?? j { JStr _ → T _ → F }
}

@ json_is_arr Json j → b {
    ^ ?? j { JArr _ → T _ → F }
}

@ json_is_obj Json j → b {
    ^ ?? j { JObj _ → T _ → F }
}

@ json_type_name Json j → s {
    ^ ?? j {
        JNull → `null`
        JBool _ → `bool`
        JNum _ → `num`
        JStr _ → `str`
        JArr _ → `arr`
        JObj _ → `obj`
    }
}

// ── Recursive free ───────────────────────────────────────────────────
//
// Walks the tree and releases owned strings, then releases the Vec
// buffers. Containers iterate via vec_free_with so each element gets
// its own json_free. Caller passes the Json by value (handles inside
// are pointers); after the call, the handle should not be reused.

@ json_free Json j → v {
    ?? j {
        JNull → {}
        JBool _ → {}
        JNum s → ( string_free s )
        JStr s → ( string_free s )
        JArr v → {
            : ( @ v Json ) drop \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] v drop )
        }
        JObj v → {
            : ( @ v Json ) drop \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] v drop )
        }
    }
}

// ── Parser state ─────────────────────────────────────────────────────
//
// Heap-allocated so that recursive descent calls can mutate `pos`
// without threading state through return tuples. Owned by json_parse;
// freed before returning.
//
// `depth` is bumped/decremented around array/object recursion to enforce
// a hard cap (`JSON_MAX_DEPTH`) and prevent stack overflow from hostile
// payloads like `[[[[[[...]]]]]]`.

: i JSON_MAX_DEPTH 1024

: JsonParser {
    s src
    i len
    i pos
    i depth
}

@ __jp_new s txt → *JsonParser {
    : *JsonParser p # *JsonParser ( nurl_alloc Z JsonParser )
    = . p src txt
    = . p len ( nurl_str_len txt )
    = . p pos 0
    = . p depth 0
    ^ p
}

@ __jp_eof * JsonParser p → b {
    ^ >= . p pos . p len
}

// Read byte at absolute offset `k`. Returns -1 when out of range so
// the parser's main loop can distinguish "EOF" from "literal NUL byte"
// (the latter would be a parse error anyway, but callers test against
// -1, not 0). Uses a direct `*u` pointer read against the cached
// `. p src`; the historical `nurl_str_get` route incurred a fresh
// `strlen` of the whole input on every single byte (O(n²) parse over
// a 64 KB JSON spent gigabytes of bandwidth in `strlen` alone — fixed
// 2026-05-25, dropped end-to-end json_parse time ~30× on the
// `bench/json_parse` payload).
@ __jp_byte_at * JsonParser p i k → i {
    ? | < k 0 >= k . p len { ^ -1 } {}
    : s raw . p src
    : *u bp # *u raw
    ^ & 255 # i . bp k
}

@ __jp_peek * JsonParser p → i {
    ? >= . p pos . p len { ^ -1 } {}
    : s raw . p src
    : *u bp # *u raw
    ^ & 255 # i . bp . p pos
}

@ __jp_bump * JsonParser p → i {
    : i c ( __jp_peek p )
    = . p pos + . p pos 1
    ^ c
}

@ __jp_skip_ws * JsonParser p → v {
    : s raw . p src
    : *u bp # *u raw
    : i n . p len
    : ~ i k . p pos
    : ~ b more T
    ~ & more < k n {
        : i c & 255 # i . bp k
        ? | | | == c 32 == c 9 == c 10 == c 13
        { = k + k 1 }
        { = more F }
    }
    = . p pos k
}

// Match a literal keyword (e.g. `null`, `true`, `false`). Advances pos
// on success; leaves pos untouched on failure.
@ __jp_match_kw * JsonParser p s kw → b {
    : i n ( nurl_str_len kw )
    ? > + . p pos n . p len { ^ F } {}
    : s raw . p src
    : *u bp # *u raw
    : *u bk # *u kw
    : i base . p pos
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        ? != & 255 # i . bp + base k & 255 # i . bk k
        { = ok F } {}
        = k + k 1
    }
    ? ok { = . p pos + . p pos n } {}
    ^ ok
}

// ── Error construction ──────────────────────────────────────────────
//
// All parser failures route through `__jp_err`, which captures the
// current `pos` and walks `src` from byte 0 to compute (line, col). The
// returned `JsonError` carries all the diagnostic state — there are no
// globals, so nested or threaded parses don't clobber each other.
//
// Use `__jp_err_at` when the failure should point at a specific byte
// (e.g. the opening `"` of an unterminated string, not the EOF byte
// where the parser actually stopped).

@ __jp_err_at * JsonParser p i pos_override ParseErr kind → JsonError {
    : i n . p len
    : ~ i target pos_override
    ? > target n { = target n } {}
    ? < target 0 { = target 0 } {}
    : s raw . p src
    : *u bp # *u raw
    : ~ i line 1
    : ~ i col 1
    : ~ i k 0
    ~ < k target {
        : i c & 255 # i . bp k
        ? == c 10 {
            = line + line 1
            = col 1
        } {
            = col + col 1
        }
        = k + k 1
    }
    ^ @ JsonError { kind target line col }
}

@ __jp_err * JsonParser p ParseErr kind → JsonError {
    ^ ( __jp_err_at p . p pos kind )
}

// ── Number ───────────────────────────────────────────────────────────
//
// Strict JSON number grammar (RFC 8259):
//   '-'? ( '0' | [1-9][0-9]* ) ( '.' [0-9]+ )? ( [eE][+-]?[0-9]+ )?
//
// Leading zeros are rejected (`01` → BadFormat) so that the serializer
// can round-trip any parsed value as valid JSON without numeric
// reformatting. The error position points at the first digit so that
// the diagnostic highlights the offending token, not a trailing byte.

@ __jp_parse_number * JsonParser p → !Json JsonError {
    : i token_start . p pos
    ? == ( __jp_peek p ) 45 { = . p pos + . p pos 1 } {}

    : i first_digit_pos . p pos
    : ~ i digit_count 0
    ~ & ! ( __jp_eof p ) != 0 ( is_digit ( __jp_peek p ) ) {
        = . p pos + . p pos 1
        = digit_count + digit_count 1
    }

    ? == digit_count 0 {
        ^ @ !Json JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
    } {}

    // RFC 8259: leading zero is only allowed when the integer part is
    // exactly `0` (so `0.5`, `0e2`, `0` ok; `01`, `007` rejected).
    ? & >= digit_count 2 == ( __jp_byte_at p first_digit_pos ) 48 {
        ^ @ !Json JsonError { F ( __jp_err_at p first_digit_pos @ ParseErr { BadFormat } ) }
    } {}

    // Optional fractional part.
    ? & ! ( __jp_eof p ) == ( __jp_peek p ) 46 {
        = . p pos + . p pos 1
        : ~ i frac_count 0
        ~ & ! ( __jp_eof p ) != 0 ( is_digit ( __jp_peek p ) ) {
            = . p pos + . p pos 1
            = frac_count + frac_count 1
        }
        ? == frac_count 0 {
            ^ @ !Json JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
        } {}
    } {}

    // Optional exponent.
    ? ! ( __jp_eof p ) {
        : i ec ( __jp_peek p )
        ? | == ec 101 == ec 69 {
            = . p pos + . p pos 1
            ? ! ( __jp_eof p ) {
                : i sgn ( __jp_peek p )
                ? | == sgn 43 == sgn 45 { = . p pos + . p pos 1 } {}
            } {}
            : ~ i exp_count 0
            ~ & ! ( __jp_eof p ) != 0 ( is_digit ( __jp_peek p ) ) {
                = . p pos + . p pos 1
                = exp_count + exp_count 1
            }
            ? == exp_count 0 {
                ^ @ !Json JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
            } {}
        } {}
    } {}

    : i n_bytes - . p pos token_start
    : s src_raw . p src
    : *u src_bp # *u src_raw
    : *u start_ptr # *u + # i src_bp token_start
    : String raw ( string_from_bytes_packed start_ptr n_bytes )
    ^ @ !Json JsonError { T @ Json { JNum raw } }
}

// ── String ───────────────────────────────────────────────────────────
//
// Reads a `"..."` string. Decodes \" \\ \/ \n \t \r \b \f and \uXXXX
// (including surrogate pairs, encoded to UTF-8 bytes). A literal byte
// stream of multi-byte UTF-8 is also accepted directly inside the
// quotes — we don't validate it, just shovel bytes through.
//
// All failure paths report the position of the opening `"` so that
// "unterminated string" points at the byte where the string starts,
// not at EOF on the other end of the file.

// Convert a single ASCII hex digit to its 0..15 value, or -1 on a
// non-hex byte.
@ __jp_hex_digit i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}  // '0'-'9'
    ? & >= c 97 <= c 102 { ^ + - c 97 10 } {}  // 'a'-'f'
    ? & >= c 65 <= c 70 { ^ + - c 65 10 } {}  // 'A'-'F'
    ^ -1
}

// Encode a Unicode code point (0..0x10FFFF) as 1–4 UTF-8 bytes and
// append them to `out`. Code points above U+10FFFF or in the
// surrogate range U+D800..U+DFFF (which should have been merged into
// a single code point by the caller) are passed through bytewise via
// the 3-byte path; downstream consumers will see invalid UTF-8 but at
// least no information is silently dropped.
@ __jp_push_utf8 String out i cp → v {
    ? <= cp 127 {
        ( string_push_char out cp )
    } {
        ? <= cp 2047 {
            ( string_push_char out | 192 >> cp 6 )
            ( string_push_char out | 128 & cp 63 )
        } {
            ? <= cp 65535 {
                ( string_push_char out | 224 >> cp 12 )
                ( string_push_char out | 128 & >> cp 6 63 )
                ( string_push_char out | 128 & cp 63 )
            } {
                ( string_push_char out | 240 >> cp 18 )
                ( string_push_char out | 128 & >> cp 12 63 )
                ( string_push_char out | 128 & >> cp 6 63 )
                ( string_push_char out | 128 & cp 63 )
            }
        }
    }
}

// Reads 4 hex digits starting at the parser's current position and
// advances past them. Returns -1 on EOF or non-hex byte.
@ __jp_read_hex4 * JsonParser p → i {
    : ~ i acc 0
    : ~ i k 0
    : ~ b bad F
    ~ & ! bad < k 4 {
        ? ( __jp_eof p ) { = bad T } {
            : i d ( __jp_hex_digit ( __jp_peek p ) )
            ? < d 0 { = bad T } {
                = acc + << acc 4 d
                = . p pos + . p pos 1
                = k + k 1
            }
        }
    }
    ? bad { ^ -1 } {}
    ^ acc
}

@ __jp_parse_string * JsonParser p → !String JsonError {
    : i token_start . p pos
    ? != ( __jp_peek p ) 34 {
        ^ @ !String JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
    } {}
    = . p pos + . p pos 1

    // Fast path: scan forward for the closing quote OR an escape. If we
    // hit the close before any backslash, the string is byte-identical
    // with its source bytes — copy the whole run with one memcpy via
    // `string_from_bytes` and skip the per-char push loop entirely. In
    // the bench/json_parse payload (RFC 8259 numbers + record-name
    // strings of the `record-00000123` shape) this fires on 100 % of
    // strings and is the difference between "slower than Python" and
    // "competitive with hand-written Rust".
    : s raw . p src
    : *u bp # *u raw
    : i len . p len
    : i body_start . p pos
    : i remaining - len body_start
    : s body_start_ptr # s + # i bp body_start
    // First locate the closing quote (the common case — every record-
    // shape string in well-formed JSON has one). memchr is SIMD-fast.
    : s close_p ( memchr body_start_ptr 34 remaining )
    ? != # i close_p 0 {
        : i close_off - # i close_p # i bp
        : i hit_len - close_off body_start
        // Then check whether the spanned range contains a backslash —
        // if not, the bytes are literal and we can memcpy-slice them
        // directly without walking the escape decoder.
        : s esc_p ( memchr body_start_ptr 92 hit_len )
        ? == # i esc_p 0 {
            : *u from # *u body_start_ptr
            : String fs ( string_from_bytes_packed from hit_len )
            = . p pos + close_off 1
            ^ @ !String JsonError { T fs }
        } {}
    } {}
    // Else: contains an escape, or no close before EOF. Fall through to
    // the canonical char-by-char loop, which handles both.
    // Else: contains an escape, or hit EOF before a close. Fall through
    // to the canonical char-by-char loop, which handles both.

    : String out ( string_with_cap 16 )
    : ~ b done F
    ~ ! done {
        ? ( __jp_eof p ) {
            ( string_free out )
            ^ @ !String JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
        } {}
        : i c ( __jp_peek p )
        ? == c 34 {
            = . p pos + . p pos 1
            = done T
        } {
            ? == c 92 {
                = . p pos + . p pos 1
                ? ( __jp_eof p ) {
                    ( string_free out )
                    ^ @ !String JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
                } {}
                : i esc ( __jp_peek p )
                = . p pos + . p pos 1
                ? == esc 34 { ( string_push_char out 34 ) } {
                    ? == esc 92 { ( string_push_char out 92 ) } {
                        ? == esc 47 { ( string_push_char out 47 ) } {
                            ? == esc 110 { ( string_push_char out 10 ) } {
                                ? == esc 116 { ( string_push_char out 9 ) } {
                                    ? == esc 114 { ( string_push_char out 13 ) } {
                                        ? == esc 98 { ( string_push_char out 8 ) } {
                                            ? == esc 102 { ( string_push_char out 12 ) } {
                                                ? == esc 117 {
                                                    // \uXXXX — read 4 hex digits, decode to a UTF-8 byte sequence.
                                                    // If the value is a high surrogate (0xD800..0xDBFF) the spec
                                                    // requires a following `\uYYYY` low surrogate (0xDC00..0xDFFF);
                                                    // combine them into a single supplementary code point. Any
                                                    // other value (including a lone low surrogate or unmatched
                                                    // high surrogate) is emitted as-is via the 3-byte path.
                                                    : i h ( __jp_read_hex4 p )
                                                    ? < h 0 {
                                                        ( string_free out )
                                                        ^ @ !String JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
                                                    } {}
                                                    ? & >= h 55296 <= h 56319 {
                                                        // Possible high surrogate — try to consume `\uYYYY`.
                                                        ? & ! ( __jp_eof p ) == ( __jp_peek p ) 92 {
                                                            = . p pos + . p pos 1
                                                            ? & ! ( __jp_eof p ) == ( __jp_peek p ) 117 {
                                                                = . p pos + . p pos 1
                                                                : i l ( __jp_read_hex4 p )
                                                                ? & >= l 56320 <= l 57343 {
                                                                    : i cp + + 65536 << - h 55296 10 - l 56320
                                                                    ( __jp_push_utf8 out cp )
                                                                } {
                                                                    // Not a valid low surrogate — emit the high alone,
                                                                    // then re-process the second `\uXXXX` as a code point.
                                                                    ( __jp_push_utf8 out h )
                                                                    ? >= l 0 { ( __jp_push_utf8 out l ) } {}
                                                                }
                                                            } {
                                                                // After `\` was no `u` — emit high alone, the `\?` got
                                                                // swallowed; best-effort recovery.
                                                                ( __jp_push_utf8 out h )
                                                            }
                                                        } {
                                                            ( __jp_push_utf8 out h )
                                                        }
                                                    } {
                                                        ( __jp_push_utf8 out h )
                                                    }
                                                } {
                                                    ( string_free out )
                                                    ^ @ !String JsonError { F ( __jp_err_at p token_start @ ParseErr { BadFormat } ) }
                                                } } } } } } } } }
            } {
                ( string_push_char out c )
                = . p pos + . p pos 1
            }
        }
    }
    ^ @ !String JsonError { T out }
}

// ── Top-level dispatch (forward declaration via mutual recursion) ────

@ __jp_parse_value * JsonParser p → !Json JsonError {
    ( __jp_skip_ws p )
    ? ( __jp_eof p ) {
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { Empty } ) }
    } {}
    : i c ( __jp_peek p )

    ? == c 110 {
        ? ( __jp_match_kw p `null` ) {
            ^ @ !Json JsonError { T @ Json { JNull } }
        } {}
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
    } {}

    ? == c 116 {
        ? ( __jp_match_kw p `true` ) {
            ^ @ !Json JsonError { T @ Json { JBool T } }
        } {}
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
    } {}

    ? == c 102 {
        ? ( __jp_match_kw p `false` ) {
            ^ @ !Json JsonError { T @ Json { JBool F } }
        } {}
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
    } {}

    ? == c 34 {
        : !String JsonError sr ( __jp_parse_string p )
        ^ ?? sr {
            T s → @ !Json JsonError { T @ Json { JStr s } }
            F e → @ !Json JsonError { F # JsonError e }
        }
    } {}

    ? == c 91 { ^ ( __jp_parse_array p ) } {}
    ? == c 123 { ^ ( __jp_parse_object p ) } {}

    ? | == c 45 != 0 ( is_digit c ) {
        ^ ( __jp_parse_number p )
    } {}

    ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
}

// Array / object are split into an outer wrapper (depth bump + decrement,
// guaranteed paired across all success AND failure paths) and an inner
// body. This keeps the depth counter accurate even if a future refactor
// reuses a single JsonParser across multiple parses.

@ __jp_parse_array * JsonParser p → !Json JsonError {
    ? >= . p depth JSON_MAX_DEPTH {
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { Overflow } ) }
    } {}
    = . p depth + . p depth 1
    : !Json JsonError r ( __jp_parse_array_body p )
    = . p depth - . p depth 1
    ^ r
}

@ __jp_parse_array_body * JsonParser p → !Json JsonError {
    = . p pos + . p pos 1  // consume '['
    : ( Vec Json ) elems ( vec_new [Json] )
    ( __jp_skip_ws p )
    ? ( __jp_eof p ) {
        : ( @ v Json ) drop1 \ Json e → v { ( json_free e ) }
        ( vec_free_with [Json] elems drop1 )
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
    } {}
    ? == ( __jp_peek p ) 93 {  // empty array
        = . p pos + . p pos 1
        ^ @ !Json JsonError { T @ Json { JArr elems } }
    } {}

    : ~ b more T
    ~ more {
        : !Json JsonError child ( __jp_parse_value p )
        ?? child {
            T jv → ( vec_push [Json] elems jv )
            F e → {
                : ( @ v Json ) drop2 \ Json e2 → v { ( json_free e2 ) }
                ( vec_free_with [Json] elems drop2 )
                ^ @ !Json JsonError { F # JsonError e }
            }
        }
        ( __jp_skip_ws p )
        ? ( __jp_eof p ) {
            : ( @ v Json ) drop3 \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] elems drop3 )
            ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
        } {}
        : i nc ( __jp_peek p )
        ? == nc 44 {  // ','
            = . p pos + . p pos 1
            ( __jp_skip_ws p )
        } {
            ? == nc 93 {  // ']'
                = . p pos + . p pos 1
                = more F
            } {
                : ( @ v Json ) drop4 \ Json e → v { ( json_free e ) }
                ( vec_free_with [Json] elems drop4 )
                ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
            }
        }
    }
    ^ @ !Json JsonError { T @ Json { JArr elems } }
}

@ __jp_parse_object * JsonParser p → !Json JsonError {
    ? >= . p depth JSON_MAX_DEPTH {
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { Overflow } ) }
    } {}
    = . p depth + . p depth 1
    : !Json JsonError r ( __jp_parse_object_body p )
    = . p depth - . p depth 1
    ^ r
}

@ __jp_parse_object_body * JsonParser p → !Json JsonError {
    = . p pos + . p pos 1  // consume '{'
    : ( Vec Json ) kvs ( vec_new [Json] )
    ( __jp_skip_ws p )
    ? ( __jp_eof p ) {
        : ( @ v Json ) drop1 \ Json e → v { ( json_free e ) }
        ( vec_free_with [Json] kvs drop1 )
        ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
    } {}
    ? == ( __jp_peek p ) 125 {  // empty object
        = . p pos + . p pos 1
        ^ @ !Json JsonError { T @ Json { JObj kvs } }
    } {}

    : ~ b more T
    ~ more {
        ( __jp_skip_ws p )
        ? != ( __jp_peek p ) 34 {
            : ( @ v Json ) drop2 \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] kvs drop2 )
            ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
        } {}
        : !String JsonError ks ( __jp_parse_string p )
        ?? ks {
            T s → ( vec_push [Json] kvs @ Json { JStr s } )
            F e → {
                : ( @ v Json ) drop3 \ Json e2 → v { ( json_free e2 ) }
                ( vec_free_with [Json] kvs drop3 )
                ^ @ !Json JsonError { F # JsonError e }
            }
        }
        ( __jp_skip_ws p )
        ? != ( __jp_peek p ) 58 {  // ':'
            : ( @ v Json ) drop4 \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] kvs drop4 )
            ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
        } {}
        = . p pos + . p pos 1
        : !Json JsonError vv ( __jp_parse_value p )
        ?? vv {
            T jv → ( vec_push [Json] kvs jv )
            F e → {
                : ( @ v Json ) drop5 \ Json e2 → v { ( json_free e2 ) }
                ( vec_free_with [Json] kvs drop5 )
                ^ @ !Json JsonError { F # JsonError e }
            }
        }
        ( __jp_skip_ws p )
        ? ( __jp_eof p ) {
            : ( @ v Json ) drop6 \ Json e → v { ( json_free e ) }
            ( vec_free_with [Json] kvs drop6 )
            ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
        } {}
        : i nc ( __jp_peek p )
        ? == nc 44 {
            = . p pos + . p pos 1
        } {
            ? == nc 125 {
                = . p pos + . p pos 1
                = more F
            } {
                : ( @ v Json ) drop7 \ Json e → v { ( json_free e ) }
                ( vec_free_with [Json] kvs drop7 )
                ^ @ !Json JsonError { F ( __jp_err p @ ParseErr { BadFormat } ) }
            }
        }
    }
    ^ @ !Json JsonError { T @ Json { JObj kvs } }
}

@ json_parse s src → !Json JsonError {
    ? == ( nurl_str_len src ) 0 {
        : JsonError e @ JsonError {
            @ ParseErr { Empty }
            0
            1
            1
        }
        ^ @ !Json JsonError { F e }
    } {}
    : *JsonParser p ( __jp_new src )
    : !Json JsonError r ( __jp_parse_value p )
    ?? r {
        T j → {
            ( __jp_skip_ws p )
            ? ! ( __jp_eof p ) {
                : JsonError e ( __jp_err p @ ParseErr { TrailingGarbage } )
                ( json_free j )
                ( nurl_free # s p )
                ^ @ !Json JsonError { F e }
            } {}
            ( nurl_free # s p )
            ^ @ !Json JsonError { T j }
        }
        F e → {
            ( nurl_free # s p )
            ^ @ !Json JsonError { F # JsonError e }
        }
    }
}

// Format a parse failure as "<kind> at line L col C". Caller owns the
// returned String.
@ json_format_error JsonError e → String {
    : String out ( string_with_cap 48 )
    ( string_push_str out ( parse_err_msg # ParseErr . e kind ) )
    ( string_push_str out ` at line ` )
    ( string_push_int out . e line )
    ( string_push_str out ` col ` )
    ( string_push_int out . e col )
    ^ out
}

// ── Stringify ────────────────────────────────────────────────────────
//
// Compact serialization with the inverse of __jp_parse_string's escape
// table. Returns a fresh String the caller owns. Output is always valid
// JSON: the parser only accepts spec-conformant numbers (no leading
// zeros), and any byte below 0x20 without a named escape (\b \t \n \f
// \r) is encoded as `\u00XX`. The result round-trips through any
// strict JSON parser (including jq, Python, JavaScript).

// Append a single ASCII hex digit (0..15) to `out`. Used by the
// `\u00XX` control-char escape path.
@ __js_hex_nibble String out i v → v {
    ? < v 10 {
        ( string_push_char out + 48 v )  // '0'..'9'
    } {
        ( string_push_char out + 87 v )  // 'a'..'f' (87 = 'a' - 10)
    }
}

@ __js_emit_str String out String s → v {
    ( string_push_char out 34 )
    : i n ( string_len s )
    : ~ i k 0
    ~ < k n {
        : i c ( string_get s k )
        ? == c 34 { ( string_push_char out 92 ) ( string_push_char out 34 ) } {
            ? == c 92 { ( string_push_char out 92 ) ( string_push_char out 92 ) } {
                ? == c 10 { ( string_push_char out 92 ) ( string_push_char out 110 ) } {
                    ? == c 9 { ( string_push_char out 92 ) ( string_push_char out 116 ) } {
                        ? == c 13 { ( string_push_char out 92 ) ( string_push_char out 114 ) } {
                            ? == c 8 { ( string_push_char out 92 ) ( string_push_char out 98 ) } {
                                ? == c 12 { ( string_push_char out 92 ) ( string_push_char out 102 ) } {
                                    ? & >= c 0 < c 32 {
                                        // Remaining control bytes (0x00..0x1F without a named
                                        // escape) → `\u00XX`. Required for strict-parser safety.
                                        ( string_push_char out 92 )  // '\\'
                                        ( string_push_char out 117 )  // 'u'
                                        ( string_push_char out 48 )  // '0'
                                        ( string_push_char out 48 )  // '0'
                                        ( __js_hex_nibble out & >> c 4 15 )
                                        ( __js_hex_nibble out & c 15 )
                                    } {
                                        ( string_push_char out c )
                                    }
                                } } } } } } }
        = k + k 1
    }
    ( string_push_char out 34 )
}

@ __js_emit_value String out Json j → v {
    ?? j {
        JNull → ( string_push_str out `null` )
        JBool b → ( string_push_str out ? b `true` `false` )
        JNum s → ( string_push_str out ( string_data s ) )
        JStr s → ( __js_emit_str out s )
        JArr v → {
            ( string_push_char out 91 )
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                ? > k 0 { ( string_push_char out 44 ) } {}
                : ?Json e ( vec_get [Json] v k )
                ?? e {
                    T jv → ( __js_emit_value out jv )
                    F → {}
                }
                = k + k 1
            }
            ( string_push_char out 93 )
        }
        JObj v → {
            ( string_push_char out 123 )
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                ? > k 0 { ( string_push_char out 44 ) } {}
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → ( __js_emit_value out jk )
                    F → {}
                }
                ? + k 1 < n {
                    ( string_push_char out 58 )
                    : ?Json ev ( vec_get [Json] v + k 1 )
                    ?? ev {
                        T jv → ( __js_emit_value out jv )
                        F → {}
                    }
                } {}
                = k + k 2
            }
            ( string_push_char out 125 )
        }
    }
}

@ json_stringify Json j → String {
    : String out ( string_with_cap 32 )
    ( __js_emit_value out j )
    ^ out
}

// ── Pretty serialization ────────────────────────────────────────────
//
// 2-space indented form. Empty arrays / objects collapse to `[]` / `{}`
// (no newline) — matches `JSON.stringify(x, null, 2)` from JS, jq's
// default output, and Python's `json.dumps(indent=2)`. The recursive
// helper threads `depth` (current nesting level) so each value's
// children indent one extra step.

@ __js_indent String out i depth → v {
    : ~ i k 0
    ~ < k depth {
        ( string_push_char out 32 )
        ( string_push_char out 32 )
        = k + k 1
    }
}

@ __js_emit_pretty_value String out Json j i depth → v {
    ?? j {
        JNull → ( string_push_str out `null` )
        JBool b → ( string_push_str out ? b `true` `false` )
        JNum s → ( string_push_str out ( string_data s ) )
        JStr s → ( __js_emit_str out s )
        JArr v → {
            : i n ( vec_len [Json] v )
            ? == n 0 {
                ( string_push_str out `[]` )
            } {
                ( string_push_char out 91 )  // '['
                ( string_push_char out 10 )  // '\n'
                : ~ i k 0
                ~ < k n {
                    ( __js_indent out + depth 1 )
                    : ?Json e ( vec_get [Json] v k )
                    ?? e {
                        T jv → ( __js_emit_pretty_value out jv + depth 1 )
                        F → {}
                    }
                    : i k_next + k 1
                    ? < k_next n { ( string_push_char out 44 ) } {}
                    ( string_push_char out 10 )
                    = k + k 1
                }
                ( __js_indent out depth )
                ( string_push_char out 93 )  // ']'
            }
        }
        JObj v → {
            : i n ( vec_len [Json] v )
            ? == n 0 {
                ( string_push_str out `{}` )
            } {
                ( string_push_char out 123 )  // '{'
                ( string_push_char out 10 )
                : ~ i k 0
                ~ < k n {
                    ( __js_indent out + depth 1 )
                    : ?Json ek ( vec_get [Json] v k )
                    ?? ek {
                        T jk → ( __js_emit_pretty_value out jk + depth 1 )
                        F → {}
                    }
                    : i k_v + k 1
                    ? < k_v n {
                        ( string_push_str out `: ` )  // ": "
                        : ?Json ev ( vec_get [Json] v k_v )
                        ?? ev {
                            T jv → ( __js_emit_pretty_value out jv + depth 1 )
                            F → {}
                        }
                    } {}
                    // Trailing comma between entries (every other index).
                    : i k_after + k 2
                    ? < k_after n { ( string_push_char out 44 ) } {}
                    ( string_push_char out 10 )
                    = k + k 2
                }
                ( __js_indent out depth )
                ( string_push_char out 125 )  // '}'
            }
        }
    }
}

@ json_pretty Json j → String {
    : String out ( string_with_cap 64 )
    ( __js_emit_pretty_value out j 0 )
    ^ out
}

// ── Accessors ────────────────────────────────────────────────────────

@ json_arr_len Json j → i {
    ^ ?? j {
        JArr v → ( vec_len [Json] v )
        _ → 0
    }
}

@ json_arr_get Json j i idx → ?Json {
    ^ ?? j {
        JArr v → ( vec_get [Json] v idx )
        _ → @ ?Json { F @ Json { JNull } }
    }
}

@ json_obj_get Json j s key → ?Json {
    ^ ?? j {
        JObj v → {
            : i n ( vec_len [Json] v )
            : ~ i k 0
            : ~ ? Json found @ ?Json { F @ Json { JNull } }
            : ~ b stop F
            ~ & ! stop < k n {
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → {
                        ?? jk {
                            JStr ks → {
                                ? != 0 ( nurl_str_eq ( string_data ks ) key ) {
                                    : ?Json ev ( vec_get [Json] v + k 1 )
                                    = found ev
                                    = stop T
                                } {}
                            }
                            _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 2
            }
            ^ found
        }
        _ → @ ?Json { F @ Json { JNull } }
    }
}

@ json_obj_has Json j s key → b {
    : ?Json e ( json_obj_get j key )
    ^ ?? e { T _ → T F → F }
}

@ json_num_as_i Json j → ?i {
    ^ ?? j {
        JNum s → {
            : !i ParseErr r ( string_to_int s )
            ^ ?? r {
                T n → @ ?i { T n }
                F → @ ?i { F 0 }
            }
        }
        _ → @ ?i { F 0 }
    }
}

@ json_num_as_f Json j → ?f {
    ^ ?? j {
        JNum s → ( string_to_float s )
        _ → @ ?f { F 0.0 }
    }
}

@ json_str_data Json j → s {
    ^ ?? j {
        JStr s → ( string_data s )
        _ → ``
    }
}

@ json_bool_val Json j → b {
    ^ ?? j {
        JBool b → b
        _ → F
    }
}

// ── Iteration & object key listing ──────────────────────────────────
//
// `json_arr_each` walks JArr elements in order, calling `f` on each.
// `json_obj_each` walks JObj key-value pairs, calling `f` with the raw
// key (borrowed `i8*`, do NOT free) and the JSON value. Both are
// no-ops on a non-matching variant — they don't fail, they just don't
// iterate anything.
//
// `json_obj_keys` returns a fresh `Vec[String]` copy of the keys; the
// caller owns the Vec and each String inside, free with
//   : (@ v String) drop \ String s → v { ( string_free s ) }
//   ( vec_free_with [String] keys drop )
// Returns an empty Vec for non-objects.

@ json_arr_each Json j ( @ v Json ) f → v {
    ?? j {
        JArr v → {
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                : ?Json e ( vec_get [Json] v k )
                ?? e {
                    T jv → ( f jv )
                    F → {}
                }
                = k + k 1
            }
        }
        _ → {}
    }
}

@ json_obj_each Json j ( @ v s Json ) f → v {
    ?? j {
        JObj v → {
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → {
                        ?? jk {
                            JStr ks → {
                                ? + k 1 < n {
                                    : ?Json ev ( vec_get [Json] v + k 1 )
                                    ?? ev {
                                        T jv → ( f ( string_data ks ) jv )
                                        F → {}
                                    }
                                } {}
                            }
                            _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 2
            }
        }
        _ → {}
    }
}

// ── Mutation helpers (build-style) ──────────────────────────────────
//
// JArr and JObj wrap a Vec[Json] heap handle. Both `json_arr_push` and
// `json_obj_set` mutate that backing buffer in-place — there is no
// rebind / no Json* needed; the user passes `j` by value, the handle
// inside reaches the same heap, and changes are visible at the call
// site. CONSUMES `elem` / `val` (and the key copy, when set creates a
// new entry): the caller must not `json_free` them after the call.
//
// Both operations return T on success, F when `j` is the wrong variant
// (the value is then NOT consumed — caller still owns it).

@ json_arr_push Json j Json elem → b {
    ^ ?? j {
        JArr v → { ( vec_push [Json] v elem )
            ^ T }
        _ → F
    }
}

// Replace value at `key` if present (frees old value), otherwise append
// a new key→val pair. The key string is copied so the caller's `key`
// raw pointer is borrowed only.
@ json_obj_set Json j s key Json val → b {
    ^ ?? j {
        JObj v → {
            : i n ( vec_len [Json] v )
            : ~ i k 0
            : ~ b done F
            ~ & ! done < k n {
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → {
                        ?? jk {
                            JStr ks → {
                                ? != 0 ( nurl_str_eq ( string_data ks ) key ) {
                                    // Key match: free old value, store new at slot k+1.
                                    : i k_v + k 1
                                    ? < k_v n {
                                        : ?Json old ( vec_get [Json] v k_v )
                                        ?? old {
                                            T ojv → ( json_free ojv )
                                            F → {}
                                        }
                                        ( vec_set [Json] v k_v val )
                                    } {
                                        // Object was malformed (odd-sized) — append val to
                                        // restore the alternating shape.
                                        ( vec_push [Json] v val )
                                    }
                                    = done T
                                } {}
                            }
                            _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 2
            }
            ? ! done {
                // No match → append fresh pair.
                : i klen ( nurl_str_len key )
                : String kc ( string_with_cap klen )
                ( string_push_str kc key )
                ( vec_push [Json] v @ Json { JStr kc } )
                ( vec_push [Json] v val )
            } {}
            ^ T
        }
        _ → F
    }
}

@ json_obj_keys Json j → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? j {
        JObj v → {
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → {
                        ?? jk {
                            JStr ks → {
                                : i klen ( string_len ks )
                                : String copy ( string_with_cap klen )
                                : ~ i ci 0
                                ~ < ci klen {
                                    ( string_push_char copy ( string_get ks ci ) )
                                    = ci + ci 1
                                }
                                ( vec_push [String] out copy )
                            }
                            _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 2
            }
        }
        _ → {}
    }
    ^ out
}

// ── Deep copy ───────────────────────────────────────────────────────
//
// Recursively duplicates the entire tree. The caller owns the returned
// Json and is responsible for `json_free`-ing it. This is the standard
// "clone before sharing" idiom: pass the clone to a consumer that takes
// ownership while keeping the original.

@ __js_clone_string String src → String {
    ^ ( string_from ( string_data src ) )
}

// ── Lenient leaf unwrappers ─────────────────────────────────────────
//
// `json_as_*` are convenience extractors that fall back to a default
// (empty / 0 / F) for the wrong variant. Use `json_is_*` first if
// strictness matters.
//
// `json_as_str` returns a BORROWED view into the underlying JStr's
// String backing buffer — valid only while the source Json lives.
// Copy via `string_from` if you need a longer-lived String.
//
// `json_as_int` vs `json_num_as_i`: both project a Json to an integer,
// but with different strictness:
//   - `json_num_as_i` returns `? i` and only succeeds on JNum whose
//     textual value parses as a valid integer (no fraction, no overflow).
//     Use it when caller cares about parse failure.
//   - `json_as_int`   returns plain `i`, never fails. It accepts JBool
//     (T→1, F→0) and falls back to 0 for everything else. JNum is
//     parsed via lenient `nurl_str_to_int` (returns 0 on failure).
//     Use it in hot paths where 0 is a reasonable default.
// Pick `json_num_as_i` when validating untrusted input; pick
// `json_as_int` when the field has already been schema-checked.

@ json_as_str Json j → s {
    ^ ?? j {
        JStr s → ( string_data s )
        _ → ``
    }
}

@ json_as_int Json j → i {
    ^ ?? j {
        JNum s → ( nurl_str_to_int ( string_data s ) )
        JBool b → ? b 1 0
        _ → 0
    }
}

@ json_as_bool Json j → b {
    ^ ?? j {
        JBool b → b
        _ → F
    }
}

@ json_clone Json j → Json {
    ^ ?? j {
        JNull → @ Json { JNull }
        JBool b → @ Json { JBool b }
        JNum s → @ Json { JNum ( __js_clone_string s ) }
        JStr s → @ Json { JStr ( __js_clone_string s ) }
        JArr v → {
            : i n ( vec_len [Json] v )
            : ( Vec Json ) dup ( vec_with_cap [Json] n )
            : ~ i k 0
            ~ < k n {
                : ?Json e ( vec_get [Json] v k )
                ?? e {
                    T jv → ( vec_push [Json] dup ( json_clone jv ) )
                    F → {}
                }
                = k + k 1
            }
            ^ @ Json { JArr dup }
        }
        JObj v → {
            : i n ( vec_len [Json] v )
            : ( Vec Json ) dup ( vec_with_cap [Json] n )
            : ~ i k 0
            ~ < k n {
                : ?Json e ( vec_get [Json] v k )
                ?? e {
                    T jv → ( vec_push [Json] dup ( json_clone jv ) )
                    F → {}
                }
                = k + k 1
            }
            ^ @ Json { JObj dup }
        }
    }
}

// ── Structural equality ─────────────────────────────────────────────
//
// Two Json values compare equal when they share the same variant AND
// their payloads compare equal. JNum equality is byte-exact on the raw
// text — `1.0` ≠ `1.00` ≠ `1`, by design (the parser preserves source
// text). For numeric equality after parse, project both sides via
// `json_num_as_f` and compare doubles. JObj equality is order-sensitive:
// `{"a":1,"b":2}` ≠ `{"b":2,"a":1}`. This matches the Vec backing
// store and avoids the cost of order-independent comparison; build a
// HashMap if you need set semantics.

@ __js_str_eq String a String b → b {
    ^ != 0 ( nurl_str_eq ( string_data a ) ( string_data b ) )
}

@ json_eq Json a Json b → b {
    ^ ?? a {
        JNull → ?? b { JNull → T _ → F }
        JBool x → ?? b { JBool y → == x y _ → F }
        JNum sx → ?? b { JNum sy → ( __js_str_eq sx sy ) _ → F }
        JStr sx → ?? b { JStr sy → ( __js_str_eq sx sy ) _ → F }
        JArr vx → ?? b {
            JArr vy → {
                : i nx ( vec_len [Json] vx )
                : i ny ( vec_len [Json] vy )
                ? != nx ny { ^ F } {}
                : ~ i k 0
                : ~ b ok T
                ~ & ok < k nx {
                    : ?Json ex ( vec_get [Json] vx k )
                    : ?Json ey ( vec_get [Json] vy k )
                    ?? ex {
                        T jx → {
                            ?? ey {
                                T jy → { ? ! ( json_eq jx jy ) { = ok F } {} }
                                F → { = ok F }
                            }
                        }
                        F → { = ok F }
                    }
                    = k + k 1
                }
                ^ ok
            }
            _ → F
        }
        JObj vx → ?? b {
            JObj vy → {
                : i nx ( vec_len [Json] vx )
                : i ny ( vec_len [Json] vy )
                ? != nx ny { ^ F } {}
                : ~ i k 0
                : ~ b ok T
                ~ & ok < k nx {
                    : ?Json ex ( vec_get [Json] vx k )
                    : ?Json ey ( vec_get [Json] vy k )
                    ?? ex {
                        T jx → {
                            ?? ey {
                                T jy → { ? ! ( json_eq jx jy ) { = ok F } {} }
                                F → { = ok F }
                            }
                        }
                        F → { = ok F }
                    }
                    = k + k 1
                }
                ^ ok
            }
            _ → F
        }
    }
}

// ── Path access ─────────────────────────────────────────────────────
//
// Dotted path navigation: `"user.items.0.name"`. Each segment is split
// on `.`. A purely-numeric segment is treated as an array index;
// otherwise as an object key. So `"items.0"` and `"items[0]"` (using
// array-bracket syntax) are NOT equivalent — only the dotted form is
// supported here, keeping the parser trivial.
//
// Empty path → returns `j` itself (wrapped Some). Returns None at the
// first missing segment, type mismatch, or out-of-range index.
//
// The returned Json is BORROWED from inside `j` — do not free it
// independently. Free `j` when done.

@ __js_seg_is_int s seg → b {
    : i n ( nurl_str_len seg )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : i c ( nurl_str_at seg n k )
        ? == 0 ( is_digit c ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

@ json_get Json j s path → ?Json {
    : i pn ( nurl_str_len path )
    ? == pn 0 { ^ @ ?Json { T j } } {}

    // Local cursor — we walk a Json by value through the segments.
    : ~ Json cur j
    : ~ i seg_start 0
    : ~ i k 0
    : ~ b miss F
    ~ & ! miss <= k pn {
        // Treat '.' or end-of-string as a segment boundary.
        : b boundary | == k pn == ( nurl_str_at path pn k ) 46
        ? boundary {
            : i seg_len - k seg_start
            ? == seg_len 0 {
                // Empty segment (leading ".", "..") → reject.
                = miss T
            } {
                : String seg ( string_with_cap seg_len )
                : ~ i si seg_start
                ~ < si k {
                    ( string_push_char seg ( nurl_str_at path pn si ) )
                    = si + si 1
                }
                : s seg_raw ( string_data seg )
                ? ( __js_seg_is_int seg_raw ) {
                    : !i ParseErr ri ( string_to_int seg )
                    ?? ri {
                        T idx → {
                            : ?Json next ( json_arr_get cur idx )
                            ?? next {
                                T jv → { = cur jv }
                                F → { = miss T }
                            }
                        }
                        F → { = miss T }
                    }
                } {
                    : ?Json next ( json_obj_get cur seg_raw )
                    ?? next {
                        T jv → { = cur jv }
                        F → { = miss T }
                    }
                }
                ( string_free seg )
                = seg_start + k 1
            }
        } {}
        = k + k 1
    }
    ? miss { ^ @ ?Json { F @ Json { JNull } } } {}
    ^ @ ?Json { T cur }
}
