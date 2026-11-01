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
//   ( json_float x )                  → Json    JNum from primitive float (NaN / ±inf → JNull)
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
//   ( json_parse raw )                → ! Json JsonError   raw as s; ends at NUL
//   ( json_parse_n raw len )          → ! Json JsonError   exact byte range (the root
//                                       entry — an embedded NUL is rejected, not truncated);
//                                       raw as *u: `unsafe` code only (safe: json_parse_bytes)
//   ( json_parse_bytes buf )          → ! Json JsonError   ( Vec u ), borrowed
//   ( json_parse_slice text )         → ! Json JsonError   ( Slice u ): a window, a db cell
//   ( json_stringify j )              → String  compact (always valid JSON)
//   ( json_write out j )              → v       the same text appended to a ( Vec u )
//   ( json_pretty    j )              → String  2-space indented
//   ( json_format_error e )           → String  "<kind> at line L col C" (caller owns)
//
// Streaming writer (no Json values: straight into a ( Vec u ) — see
// "Streaming writer" below):
//   ( json_writer )                   → JsonWriter
//   ( jw_obj w out ) / jw_arr / jw_end / ( jw_key w out key )
//   ( jw_str w out s ) / jw_string / jw_str_slice / jw_int / jw_float /
//   jw_bool / jw_null / ( jw_json w out j ) / jw_raw / jw_raw_slice
//   ( jw_ok w )                       → b       one whole value, no misuse
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
//   - Max nesting depth is `JSON_MAX_DEPTH` (256, as XML_MAX_DEPTH and
//     YAML_MAX_DEPTH) — guards against stack-blowing payloads like
//     `[[[[[[…]]]]]]`, sized for a fiber's 64 KB stack (see below).
//   - `json_get` paths split on `.`. A purely-numeric segment ALWAYS
//     means array index — there is no escape syntax to reach a numeric
//     key in an object via path; use `json_obj_get` directly for those.
//   - Duplicate object keys are preserved; first-match wins for lookup.
//     If you need set semantics, project into a HashMap.

$ `stdlib/core/errors.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/bytes.nu`

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
    // JSON has no NaN and no infinity: `nan` in the output is a document
    // no parser accepts, and a dashboard that reads such a listing gets
    // nothing at all. The value that is not a number is `null` — what
    // JavaScript's JSON.stringify writes for the same double.
    ? | != 0 ( nurl_is_nan x ) != 0 ( nurl_is_inf x ) { ^ @ Json { JNull } } {}
    : ( Vec u ) digits ( vec_with_cap [u] 24 )
    ( __json_float_digits digits x )
    ^ @ Json { JNum ( string_from_vec digits ) }
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

// ── Release ──────────────────────────────────────────────────────────

// Early release. A Json owns its strings and children and is dropped by
// whoever owns it (docs/MEMORY.md §7.6); taking it here as `sink` is what
// releases it now — the parameter is dropped on the way out.
@ json_free sink Json j → v {}

// ── Parser state ─────────────────────────────────────────────────────
//
// The parser lives in json_parse_n's frame; every step reaches it through
// its place (`*JsonParser`) and answers whether it succeeded, a `b`:
//
//   - A value a step parses goes onto `stack`: the values read and not
//     yet in their container. An array or object notes where its members
//     start on the stack, and at its closing bracket moves them into a
//     Vec of exactly their count whose buffer shares its handle's
//     allocation (vec_split_off_packed): one allocation per container
//     and no spare room. Growing each container from a guess cost two
//     allocations and its slack, and a reallocation past eight members.
//     The stack itself is one allocation for the whole parse, room for
//     sixteen values in its handle's own block (vec_with_cap_packed),
//     released with the parser.
//   - A failure records its kind and the byte it points at (`ekind`,
//     `epos`, __jp_fail) and answers F, which every caller hands straight
//     up. The line and column are worked out once, at the root. A
//     `!Json JsonError` per step carried a value and an error side by
//     side, written whole at every return and copied at every level:
//     most of what a small document cost.
//
// `depth` is bumped/decremented around array/object recursion to enforce
// a hard cap (`JSON_MAX_DEPTH`) and prevent stack overflow from hostile
// payloads like `[[[[[[...]]]]]]`. Every walk of a Json recurses once per
// level: this parser (64 bytes a level), json_stringify / json_write /
// json_pretty (__json_emit, 128) and the value's drop (64, nurl_vec_drop).
// The cap is what keeps them inside the stack they run on, and a fiber's
// is 64 KB (an async HTTP server's handler parses its body on one): 256
// levels is 32 KB at the worst, the rest left to the handler. Under the
// old cap of 1024, a body of 250 `[` then 250 `]` crashed the whole
// server: a SIGSEGV on the fiber's guard page, in the parse while it took
// 352 bytes a level, and in json_stringify from 550 levels after that
// (agora #297; compiler/tests/json_deep_fiber.nu).

: i JSON_MAX_DEPTH 256

: JsonParser {
    s src
    i len
    i pos
    i depth
    ( Vec Json ) stack
    ParseErr ekind
    i epos
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

@ __jp_skip_ws * JsonParser p → v {
    : s raw . p src
    : *u bp # *u raw
    : i n . p len
    : ~ i k . p pos
    ~ < k n {
        : i c & 255 # i . bp k
        // Most calls start on a token (compact JSON has no whitespace at
        // all): one compare finds that.
        ? > c 32 { break } {}
        ? | | | == c 32 == c 9 == c 10 == c 13 { = k + k 1 } { break }
    }
    = . p pos k
}

// Match a literal keyword `n` bytes long (`null`, `true`, `false`).
// Advances pos on success; leaves pos untouched on failure.
@ __jp_match_kw * JsonParser p s kw i n → b {
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
// Every failure goes through `__jp_fail`, which records its kind and the
// byte it points at: the current `pos`, or a byte of its own (the opening
// `"` of an unterminated string, not the EOF byte where the parser
// stopped). At the root `__jp_err_at` walks `src` from byte 0 to that byte
// for (line, col). The `JsonError` carries all the diagnostic state —
// there are no globals, so nested or threaded parses don't clobber each
// other.

// Record a failure at byte `at` and answer F, for the caller to return.
@ __jp_fail * JsonParser p i at ParseErr kind → b {
    = . p ekind kind
    = . p epos at
    ^ F
}

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

// ── Number ───────────────────────────────────────────────────────────
//
// Strict JSON number grammar (RFC 8259):
//   '-'? ( '0' | [1-9][0-9]* ) ( '.' [0-9]+ )? ( [eE][+-]?[0-9]+ )?
//
// Leading zeros are rejected (`01` → BadFormat) so that the serializer
// can round-trip any parsed value as valid JSON without numeric
// reformatting. The error position points at the first digit so that
// the diagnostic highlights the offending token, not a trailing byte.

@ __jp_number * JsonParser p → b {
    : i token_start . p pos
    ? == ( __jp_peek p ) 45 { = . p pos + . p pos 1 } {}

    : i first_digit_pos . p pos
    : ~ i digit_count 0
    ~ & ! ( __jp_eof p ) != 0 ( is_digit ( __jp_peek p ) ) {
        = . p pos + . p pos 1
        = digit_count + digit_count 1
    }

    ? == digit_count 0 {
        ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
    } {}

    // RFC 8259: leading zero is only allowed when the integer part is
    // exactly `0` (so `0.5`, `0e2`, `0` ok; `01`, `007` rejected).
    ? & >= digit_count 2 == ( __jp_byte_at p first_digit_pos ) 48 {
        ^ ( __jp_fail p first_digit_pos @ ParseErr { BadFormat } )
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
            ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
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
                ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
            } {}
        } {}
    } {}

    : i n_bytes - . p pos token_start
    : s src_raw . p src
    : *u src_bp # *u src_raw
    : *u start_ptr # *u + # i src_bp token_start
    ( vec_push [Json] . p stack @ Json { JNum ( string_from_bytes_packed start_ptr n_bytes ) } )
    ^ T
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
// append them to `out`.
//
// A surrogate half (U+D800..U+DFFF) and anything past U+10FFFF have no
// UTF-8 encoding at all, so they become U+FFFD. This used to run them
// through the 3-byte path, which emitted WTF-8: `["\uD800"]` parsed to
// the bytes ED A0 80 and json_stringify handed them straight back, so
// the module's own promise — the serializer's output is valid JSON —
// was false for any input carrying a lone surrogate (RFC 8259 §8.1
// requires the text to be UTF-8, and ED A0 80 is not). Replacing here
// rather than at the call sites is deliberate: this is the single
// choke point every code point passes through, so no future caller can
// reintroduce the hole.
@ __jp_push_utf8 String out i cp → v {
    : ~ i c cp
    ? | | < c 0 > c 1114111 & >= c 55296 <= c 57343 { = c 65533 } {}
    ? <= c 127 {
        ( string_push_char out c )
    } {
        ? <= c 2047 {
            ( string_push_char out | 192 >> c 6 )
            ( string_push_char out | 128 & c 63 )
        } {
            ? <= c 65535 {
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

// Bit j set: byte j of the 16 in `blk` is one a string's body cannot
// hold verbatim — the quote, a backslash or a byte below 32 (unsigned, so
// UTF-8's high bytes pass; RFC 8259 §7: U+0000..U+001F must be escaped
// inside a string, a raw one makes the document invalid). The parser's scan for a string's end and the
// writer's escaper both step sixteen bytes at a time on it, the shape of
// std/simd.nu's scanners: one compare per byte class per block, and
// `nurl_ctz` names the first byte.
@ __json_special16 v128 blk → i {
    : i q ( nurl_v128_eqmask8 blk ( nurl_v128_bcast8 34 ) )
    : i bs ( nurl_v128_eqmask8 blk ( nurl_v128_bcast8 92 ) )
    ^ | | q bs ( nurl_v128_ltmask8 blk ( nurl_v128_bcast8 32 ) )
}

// The offset of the first such byte in [span, span+n), or -1. Sixteen
// bytes a step; the last 1..15 come in through nurl_v128_ldn, which reads
// no byte past them and pads with zeros that the mask then leaves out —
// so a short string, the common one, is a single step whatever its
// alignment, with no byte loop at either end.
//
// The walk reads through a raw pointer: `span` points into the middle of
// the document, so `nurl_str_get`'s per-call strlen would run to the
// document's END on every byte — the scan that shipped with the
// conformance fix did exactly that and took json_parse from fastest in
// the benchmark table (8.8 ms) to slowest (42 ms).
@ __jp_span_special s span i n → i {
    : ~ i k 0
    ~ < k n {
        : i r - n k
        : i lim ? < r 16 r 16
        : i m & ( __json_special16 ( nurl_v128_ldn # s + # i span k lim ) ) - << 1 lim 1
        ? != m 0 { ^ + k # i ( nurl_ctz # u64 m ) } {}
        = k + k 16
    }
    ^ -1
}

// The string at pos, pushed onto the stack as a JStr: a value, or an
// object's key (its entry before the value's).
@ __jp_string * JsonParser p → b {
    : i token_start . p pos
    ? != ( __jp_peek p ) 34 {
        ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
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
    // The first byte that is not copied verbatim: when it is the closing
    // quote, the whole body is literal (no escape, no raw control byte)
    // and becomes the String in one memcpy.
    : i stop ( __jp_span_special body_start_ptr remaining )
    ? >= stop 0 {
        ? == 34 & # i . bp + body_start stop 255 {
            : *u from # *u body_start_ptr
            = . p pos + + body_start stop 1
            ( vec_push [Json] . p stack @ Json { JStr ( string_from_bytes_packed from stop ) } )
            ^ T
        } {}
    } {}
    // Else a backslash, a raw control byte or EOF before any close: the
    // canonical char-by-char loop decodes the escapes, and rejects a
    // control byte or the missing quote at the same position it always has.

    : String out ( string_with_cap 16 )
    : ~ b done F
    ~ ! done {
        ? ( __jp_eof p ) {
            ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
        } {}
        : i c ( __jp_peek p )
        ? == c 34 {
            = . p pos + . p pos 1
            = done T
        } {
            ? == c 92 {
                = . p pos + . p pos 1
                ? ( __jp_eof p ) {
                    ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
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
                                                    // \uXXXX — read 4 hex digits, decode to a UTF-8 byte
                                                    // sequence. A high surrogate (0xD800..0xDBFF) pairs with a
                                                    // following `\uYYYY` low surrogate (0xDC00..0xDFFF) into one
                                                    // supplementary code point. The pairing LOOKAHEAD is pure:
                                                    // it consumes `\u` only after BOTH bytes matched, so a
                                                    // `\uD800\"` leaves the `\"` escape intact for the ordinary
                                                    // loop (the old code swallowed the backslash — JSONTestSuite
                                                    // n_string_1_surrogate_then_escape parsed CLEAN with a stolen
                                                    // quote). Once `\u` is consumed the four digits MUST be hex:
                                                    // a malformed escape is a syntax error everywhere else, and
                                                    // the old "best-effort" fallthrough silently dropped it (five
                                                    // more n_ cases accepted). A complete-but-unpaired surrogate
                                                    // is NOT a syntax error (RFC 8259 leaves it undefined) — it
                                                    // becomes U+FFFD via __jp_push_utf8, and the value that broke
                                                    // the pair re-enters the loop so `\uD800\uD834\uDD1E` still
                                                    // pairs the clef. The i_ conformance class pins the policy.
                                                    : i h ( __jp_read_hex4 p )
                                                    ? < h 0 {
                                                        ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
                                                    } {}
                                                    : ~ i cur h
                                                    : ~ b done F
                                                    ~ ! done {
                                                        ? & & >= cur 55296 <= cur 56319
                                                        & == ( __jp_byte_at p . p pos ) 92 == ( __jp_byte_at p + . p pos 1 ) 117
                                                        {
                                                            = . p pos + . p pos 2
                                                            : i l ( __jp_read_hex4 p )
                                                            ? < l 0 {
                                                                ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
                                                            } {}
                                                            ? & >= l 56320 <= l 57343 {
                                                                ( __jp_push_utf8 out + + 65536 << - cur 55296 10 - l 56320 )
                                                                = done T
                                                            } {
                                                                ( __jp_push_utf8 out cur )
                                                                = cur l
                                                            }
                                                        } {
                                                            ( __jp_push_utf8 out cur )
                                                            = done T
                                                        }
                                                    }
                                                } {
                                                    ^ ( __jp_fail p token_start @ ParseErr { BadFormat } )
                                                } } } } } } } } }
            } {
                // The other half of the §7 check: a string that DOES
                // carry an escape falls through to this loop, so the
                // fast path's scan never sees it.
                ? < c 32 {
                    ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } )
                } {}
                ( string_push_char out c )
                = . p pos + . p pos 1
            }
        }
    }
    ( vec_push [Json] . p stack @ Json { JStr out } )
    ^ T
}

// ── Top-level dispatch (forward declaration via mutual recursion) ────

// One value at pos (after any whitespace), pushed onto the stack.
@ __jp_value * JsonParser p → b {
    ( __jp_skip_ws p )
    : i c ( __jp_peek p )  // -1 at the end
    ? == c 34 { ^ ( __jp_string p ) } {}
    ? == c 91 { ^ ( __jp_array p ) } {}
    ? == c 123 { ^ ( __jp_object p ) } {}
    ? | == c 45 & >= c 48 <= c 57 { ^ ( __jp_number p ) } {}
    ? & == c 110 ( __jp_match_kw p `null` 4 ) {
        ( vec_push [Json] . p stack @ Json { JNull } )
        ^ T
    } {}
    ? & == c 116 ( __jp_match_kw p `true` 4 ) {
        ( vec_push [Json] . p stack @ Json { JBool T } )
        ^ T
    } {}
    ? & == c 102 ( __jp_match_kw p `false` 5 ) {
        ( vec_push [Json] . p stack @ Json { JBool F } )
        ^ T
    } {}
    ? < c 0 { ^ ( __jp_fail p . p pos @ ParseErr { Empty } ) } {}
    ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } )
}

// An array or object closes: the members it pushed since `base` move
// into a Vec of exactly their count (one allocation, core/vec.nu), and the
// container takes their place on the stack.
@ __jp_array * JsonParser p → b {
    ? >= . p depth JSON_MAX_DEPTH { ^ ( __jp_fail p . p pos @ ParseErr { Overflow } ) } {}
    = . p depth + . p depth 1
    = . p pos + . p pos 1  // consume '['
    : i base ( vec_len [Json] . p stack )
    ( __jp_skip_ws p )
    : i first ( __jp_peek p )
    ? < first 0 { ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } ) } {}
    ? != first 93 {
        : ~ b more T
        ~ more {
            ? ! ( __jp_value p ) { ^ F } {}
            ( __jp_skip_ws p )
            : i nc ( __jp_peek p )
            ? == nc 44 { = . p pos + . p pos 1 } {
                ? != nc 93 { ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } ) } {}
                = more F
            }
        }
    } {}
    = . p pos + . p pos 1  // consume ']'
    = . p depth - . p depth 1
    ( vec_push [Json] . p stack @ Json { JArr ( vec_split_off_packed [Json] . p stack base ) } )
    ^ T
}

// The members alternate on the stack, key (a JStr) then value — JObj's
// own layout, so closing the object is the array's move.
@ __jp_object * JsonParser p → b {
    ? >= . p depth JSON_MAX_DEPTH { ^ ( __jp_fail p . p pos @ ParseErr { Overflow } ) } {}
    = . p depth + . p depth 1
    = . p pos + . p pos 1  // consume '{'
    : i base ( vec_len [Json] . p stack )
    ( __jp_skip_ws p )
    : i first ( __jp_peek p )
    ? < first 0 { ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } ) } {}
    ? != first 125 {
        : ~ b more T
        ~ more {
            ( __jp_skip_ws p )
            // The key: anything but a string fails there, BadFormat at pos.
            ? ! ( __jp_string p ) { ^ F } {}
            ( __jp_skip_ws p )
            ? != ( __jp_peek p ) 58 { ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } ) } {}  // ':'
            = . p pos + . p pos 1
            ? ! ( __jp_value p ) { ^ F } {}
            ( __jp_skip_ws p )
            : i nc ( __jp_peek p )
            ? == nc 44 { = . p pos + . p pos 1 } {
                ? != nc 125 { ^ ( __jp_fail p . p pos @ ParseErr { BadFormat } ) } {}
                = more F
            }
        }
    } {}
    = . p pos + . p pos 1  // consume '}'
    = . p depth - . p depth 1
    ( vec_push [Json] . p stack @ Json { JObj ( vec_split_off_packed [Json] . p stack base ) } )
    ^ T
}

// Byte-buffer entry: parse exactly the buffer's bytes (a network
// payload, a read_file_bytes result). BORROWS the Vec — the caller
// still owns and frees it.
@ json_parse_bytes ( Vec u ) buf → !Json JsonError {
    ^ ( json_parse_n # s ( vec_data [u] buf ) ( vec_len [u] buf ) )
}

// View entry: parse exactly the bytes `text` views — a window of a
// buffer, a database cell (psql's pg_row_view), a String's bytes — with
// no copy of them first. The Json owns everything it holds; the view
// stays the caller's.
@ json_parse_slice ( Slice u ) text → !Json JsonError {
    ^ ( json_parse_n ( slice_data [u] text ) ( slice_len [u] text ) )
}

// C-string entry: the document ends at the first NUL. A payload that
// may legitimately carry stray NUL bytes (a network buffer, a file
// read as bytes) must go through json_parse_bytes (json_parse_n in
// `unsafe` code) — through this entry a `123\0garbage` payload would
// TRUNCATE at the NUL and parse clean
// (JSONTestSuite n_multidigit_number_then_00).
@ json_parse s src → !Json JsonError {
    ^ ( json_parse_n src ( nurl_str_len src ) )
}

// Length-carrying entry — the root parser. Never reads past `len`, so
// an embedded NUL is an ordinary byte: inside a string it is a bare
// control character (BadFormat), between tokens it is an unexpected
// byte (BadFormat) — rejected, never silently truncated.
@ json_parse_n * u src i len → !Json JsonError {
    ? <= len 0 {
        : JsonError e @ JsonError {
            @ ParseErr { Empty }
            0
            1
            1
        }
        ^ @ !Json JsonError { F e }
    } {}
    : ~ JsonParser jp @ JsonParser {
        # s src
        len
        0
        0
        ( vec_with_cap_packed [Json] 16 )
        @ ParseErr { BadFormat }
        0
    }
    ^ ( __jp_parse_root jp )
}

@ __jp_parse_root inout JsonParser jp → !Json JsonError {
    : *JsonParser p ( mem_addr jp )
    : ~ b ok ( __jp_value p )
    ? ok {
        ( __jp_skip_ws p )
        ? < . p pos . p len { = ok ( __jp_fail p . p pos @ ParseErr { TrailingGarbage } ) } {}
    } {}
    ? ok {
        // The one value left on the stack is the document.
        ?? ( vec_pop [Json] . p stack ) {
            T j → { ^ @ !Json JsonError { T j } }
            F _ → {}
        }
    } {}
    ^ @ !Json JsonError { F ( __jp_err_at p . p epos . p ekind ) }
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
// Compact serialization with the inverse of __jp_string's escape
// table, appended to a byte buffer: json_write onto one the caller has
// (an HttpResponse body), json_stringify onto a fresh one it hands over
// as a String (no copy). Output is always valid JSON: the parser only
// accepts spec-conformant numbers (no leading zeros), and any byte below
// 0x20 without a named escape (\b \t \n \f \r) is encoded as `\u00XX`.
// The result round-trips through any strict JSON parser (including jq,
// Python, JavaScript). The streaming writer below emits through the same
// helpers, so a document written either way is the same text.

// `text` as a JSON string, quoted and escaped onto `out`: `"` and `\` and
// the control bytes with a named escape as that, the other control bytes
// as \u00XX, every other byte as it is (UTF-8 passes through).
//
// Emitted through a cursor, as core/string.nu's "Bulk emission cursor"
// emits a String: the room for the quotes and every byte as it is is
// reserved once and written straight through the buffer, and the length
// committed at the end. The text goes sixteen bytes a step
// (__json_special16): the run up to the next byte that needs an escape
// is one partial vector store, so a key or value with nothing to escape
// — nearly all of them, and most under sixteen bytes — is one load, one
// mask and one store. An escape is up to six bytes where one was
// reserved, so it first commits what is written and reserves the room
// for itself, the rest of the text and the closing quote. Invariant
// before byte k: the room past `w` holds the n - k bytes left, the
// closing quote and a tail byte. (A per-byte push re-reads the buffer's control block
// for every byte; a memcpy per run paid a call for each of a document's
// many short keys and values.)
@ __json_escape ( Vec u ) out ( Slice u ) text → v { ( __json_str out text 0 0 ) }

// …with `lead` and `tail`, when not 0, a byte before the opening quote and
// one after the closing quote — a member's comma, a key's colon — in the
// same reservation and the same length commit as the string.
@ __json_str ( Vec u ) out ( Slice u ) text i lead i tail → v {
    : i n . text len
    : *u src . text data
    : ~ i w ( vec_len [u] out )
    ( vec_reserve [u] out + n 4 )
    : ~ * u dst ( vec_data [u] out )
    ? > lead 0 {
        = . dst w # u lead
        = w + w 1
    } {}
    = . dst w # u 34
    = w + w 1
    : ~ i k 0
    ~ < k n {
        // Sixteen bytes a step (the last 1..15 zero-padded, the padding
        // masked off): the run before the first byte that needs an escape
        // goes out as it came, in one partial store.
        : i r - n k
        : i lim ? < r 16 r 16
        : v128 blk ( nurl_v128_ldn # s + # i src k lim )
        : i m & ( __json_special16 blk ) - << 1 lim 1
        : i run ? == m 0 lim # i ( nurl_ctz # u64 m )
        ( nurl_v128_stn # s + # i dst w run blk )
        = w + w run
        = k + k run
        ? != m 0 {
            : i c & # i . src k 255
            : b _held ( vec_set_len [u] out w )
            ( vec_reserve [u] out + - n k 8 )
            = dst ( vec_data [u] out )
            = . dst w # u 92
            : i named ? == c 34 34 ? == c 92 92 ? == c 10 110 ? == c 9 116 ? == c 13 114 ? == c 8 98 ? == c 12 102 0
            ? > named 0 {
                = . dst + w 1 # u named
                = w + w 2
            } {
                : i hi >> c 4
                : i lo & c 15
                = . dst + w 1 # u 117
                = . dst + w 2 # u 48
                = . dst + w 3 # u 48
                = . dst + w 4 # u ? < hi 10 + 48 hi + 87 hi
                = . dst + w 5 # u ? < lo 10 + 48 lo + 87 lo
                = w + w 6
            }
            = k + k 1
        } {}
    }
    = . dst w # u 34
    = w + w 1
    ? > tail 0 {
        = . dst w # u tail
        = w + w 1
    } {}
    : b _done ( vec_set_len [u] out w )
}

// A finite double's JSON text onto `out`: the shortest digits that read
// back as the same double. One that prints as bare digits (`85.0` → `85`)
// gets `.0`, or a strictly typed consumer reads it as an integer field —
// real schema drift when the value happens to land on a whole number.
// Anything with a `.` or an exponent already reads as a float.
@ __json_float_digits ( Vec u ) out f x → v {
    : s raw ( nurl_str_float x )
    : ( Slice u ) d ( slice_of_str raw )
    ( bytes_extend_slice out d )
    : i n ( slice_len [u] d )
    : ~ b plain > n 0
    : ~ i k 0
    ~ & plain < k n {
        : i c ( slice_byte d k )
        = plain | != 0 ( is_digit c ) & == c 45 == k 0
        = k + k 1
    }
    ? plain { ( bytes_extend_str out `.0` ) } {}
}

@ __json_emit ( Vec u ) out Json j → v {
    ?? j {
        JNull → ( bytes_extend_str out `null` )
        JBool b → ( bytes_extend_str out ? b `true` `false` )
        JNum s → ( bytes_extend_slice out ( string_bytes s ) )
        JStr s → ( __json_escape out ( string_bytes s ) )
        JArr v → {
            ( vec_push [u] out # u 91 )
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                ? > k 0 { ( vec_push [u] out # u 44 ) } {}
                : ?Json e ( vec_get [Json] v k )
                ?? e {
                    T jv → ( __json_emit out jv )
                    F → {}
                }
                = k + k 1
            }
            ( vec_push [u] out # u 93 )
        }
        JObj v → {
            ( vec_push [u] out # u 123 )
            : i n ( vec_len [Json] v )
            : ~ i k 0
            ~ < k n {
                ? > k 0 { ( vec_push [u] out # u 44 ) } {}
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → ( __json_emit out jk )
                    F → {}
                }
                ? < + k 1 n {
                    ( vec_push [u] out # u 58 )
                    : ?Json ev ( vec_get [Json] v + k 1 )
                    ?? ev {
                        T jv → ( __json_emit out jv )
                        F → {}
                    }
                } {}
                = k + k 2
            }
            ( vec_push [u] out # u 125 )
        }
    }
}

// `j`'s compact text appended to `out` — json_stringify's text, written
// where it is wanted (a response body, a file's buffer) with no String in
// between. `j` stays the caller's.
@ json_write ( Vec u ) out Json j → v { ( __json_emit out j ) }

@ json_stringify Json j → String {
    : ( Vec u ) out ( vec_with_cap [u] 32 )
    ( __json_emit out j )
    ^ ( string_from_vec out )
}

// ── Pretty serialization ────────────────────────────────────────────
//
// 2-space indented form. Empty arrays / objects collapse to `[]` / `{}`
// (no newline) — matches `JSON.stringify(x, null, 2)` from JS, jq's
// default output, and Python's `json.dumps(indent=2)`. The recursive
// helper threads `depth` (current nesting level) so each value's
// children indent one extra step.

@ __json_indent ( Vec u ) out i depth → v {
    : ~ i k 0
    ~ < k depth {
        ( bytes_extend_str out `  ` )
        = k + k 1
    }
}

@ __json_emit_pretty ( Vec u ) out Json j i depth → v {
    ?? j {
        JArr v → {
            : i n ( vec_len [Json] v )
            ? == n 0 {
                ( bytes_extend_str out `[]` )
            } {
                ( bytes_extend_str out `[\n` )
                : ~ i k 0
                ~ < k n {
                    ( __json_indent out + depth 1 )
                    : ?Json e ( vec_get [Json] v k )
                    ?? e {
                        T jv → ( __json_emit_pretty out jv + depth 1 )
                        F → {}
                    }
                    ? < + k 1 n { ( vec_push [u] out # u 44 ) } {}
                    ( vec_push [u] out # u 10 )
                    = k + k 1
                }
                ( __json_indent out depth )
                ( vec_push [u] out # u 93 )
            }
        }
        JObj v → {
            : i n ( vec_len [Json] v )
            ? == n 0 {
                ( bytes_extend_str out `{}` )
            } {
                ( bytes_extend_str out `{\n` )
                : ~ i k 0
                ~ < k n {
                    ( __json_indent out + depth 1 )
                    : ?Json ek ( vec_get [Json] v k )
                    ?? ek {
                        T jk → ( __json_emit_pretty out jk + depth 1 )
                        F → {}
                    }
                    ? < + k 1 n {
                        ( bytes_extend_str out `: ` )
                        : ?Json ev ( vec_get [Json] v + k 1 )
                        ?? ev {
                            T jv → ( __json_emit_pretty out jv + depth 1 )
                            F → {}
                        }
                    } {}
                    // A comma between entries (every other index).
                    ? < + k 2 n { ( vec_push [u] out # u 44 ) } {}
                    ( vec_push [u] out # u 10 )
                    = k + k 2
                }
                ( __json_indent out depth )
                ( vec_push [u] out # u 125 )
            }
        }
        _ → ( __json_emit out j )
    }
}

@ json_pretty Json j → String {
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( __json_emit_pretty out j 0 )
    ^ ( string_from_vec out )
}

// ── Streaming writer ────────────────────────────────────────────────
//
// JSON written straight into a byte buffer the caller owns — an
// HttpResponse body, a file's buffer — with no Json values in between: no
// allocation per value, and the text json_stringify would produce for the
// same document (the same escaper and number spelling). Like the protobuf
// and hpack encoders, every call names the buffer it appends to; the
// writer itself keeps only the nesting, so the separators are its
// business. A misuse — a value where an object wants a key, an end with
// nothing open, a key with no value, a second top-level value — writes
// nothing and marks the writer bad (jw_ok F) rather than emitting text
// that is not JSON.
//
//   : JsonWriter w ( json_writer )
//   ( jw_obj w out ) ( jw_arr w out )   open an object / an array (as a value)
//   ( jw_end w out )                    close the innermost one
//   ( jw_key w out key )                in an object, before each value
//   ( jw_str w out s )                  a string: s, a String (jw_string) or
//   ( jw_string w out str )             a ( Slice u ) of UTF-8 (jw_str_slice) —
//   ( jw_str_slice w out bytes )        quoted and escaped
//   ( jw_int w out n ) ( jw_float w out x ) ( jw_bool w out b ) ( jw_null w out )
//   ( jw_json w out j )                 a Json value, as json_write writes it
//   ( jw_raw w out json )               text that already is one JSON value (a
//   ( jw_raw_slice w out bytes )        jsonb cell): copied as it is — the writer
//                                       checks where it goes, not what it says
//   ( jw_ok w )                         → b  one whole value, nothing left open,
//                                       no misuse
//
//   : HttpResponse r ( response_new 200 )
//   : JsonWriter w ( json_writer )
//   ( jw_obj w . r body )
//   ( jw_key w . r body `id` ) ( jw_int w . r body 7 )
//   ( jw_end w . r body )
// The writer's state is one byte per level — [0] the top level, then
// one per open container — and every call reads and writes only the
// last: 0 the top level, empty; 7 the top level, one whole value; 1 an
// object with no member yet; 2 an object after a key; 3 an object after
// a member; 4 an array with no element yet; 5 an array after an
// element; 6 a misuse (sticky: it is never popped or overwritten).
: JsonWriter {
    ( Vec u ) st
}

@ json_writer → JsonWriter {
    : ( Vec u ) st ( vec_with_cap [u] 8 )
    ( vec_push [u] st # u 0 )
    ^ @ JsonWriter { st }
}

// Where a value may go: the separator its place wants (44, a comma after
// an earlier element; else 0) with the state moved on, or -1 with the
// writer marked bad.
@ __jw_slot JsonWriter w → i {
    : i at - ( vec_len [u] . w st ) 1
    : i s # i ( vec_at [u] . w st at )
    ? == s 5 { ^ 44 } {}
    ? == s 2 { ( vec_set [u] . w st at # u 3 ) ^ 0 } {}
    ? == s 4 { ( vec_set [u] . w st at # u 5 ) ^ 0 } {}
    ? == s 0 { ( vec_set [u] . w st at # u 7 ) ^ 0 } {}
    ( vec_set [u] . w st at # u 6 )
    ^ -1
}

// A value may go here: write the separator its place wants and say T; or
// mark the writer bad and say F.
@ __jw_value JsonWriter w ( Vec u ) out → b {
    : i sep ( __jw_slot w )
    ? > sep 0 { ( vec_push [u] out # u sep ) } {}
    ^ >= sep 0
}

@ jw_obj JsonWriter w ( Vec u ) out → v {
    ? ( __jw_value w out ) {
        ( vec_push [u] out # u 123 )
        ( vec_push [u] . w st # u 1 )
    } {}
}

@ jw_arr JsonWriter w ( Vec u ) out → v {
    ? ( __jw_value w out ) {
        ( vec_push [u] out # u 91 )
        ( vec_push [u] . w st # u 4 )
    } {}
}

@ jw_end JsonWriter w ( Vec u ) out → v {
    : i at - ( vec_len [u] . w st ) 1
    : i s # i ( vec_at [u] . w st at )
    ? | == s 1 == s 3 { ( vec_push [u] out # u 125 ) } {
        ? | == s 4 == s 5 { ( vec_push [u] out # u 93 ) } {
            ( vec_set [u] . w st at # u 6 )
            ^ v
        }
    }
    : ?u _closed ( vec_pop [u] . w st )
}

// A key is the separator, the quoted key and its colon in one write.
@ jw_key JsonWriter w ( Vec u ) out s key → v {
    : i at - ( vec_len [u] . w st ) 1
    : i s # i ( vec_at [u] . w st at )
    ? & != s 3 != s 1 {
        ( vec_set [u] . w st at # u 6 )
        ^ v
    } {}
    ( vec_set [u] . w st at # u 2 )
    ( __json_str out ( slice_of_str key ) ? == s 3 44 0 58 )
}

@ jw_str JsonWriter w ( Vec u ) out s value → v {
    : i sep ( __jw_slot w )
    ? >= sep 0 { ( __json_str out ( slice_of_str value ) sep 0 ) } {}
}

@ jw_string JsonWriter w ( Vec u ) out String value → v {
    : i sep ( __jw_slot w )
    ? >= sep 0 { ( __json_str out ( string_bytes value ) sep 0 ) } {}
}

@ jw_str_slice JsonWriter w ( Vec u ) out ( Slice u ) value → v {
    : i sep ( __jw_slot w )
    ? >= sep 0 { ( __json_str out value sep 0 ) } {}
}

@ jw_int JsonWriter w ( Vec u ) out i n → v {
    ? ( __jw_value w out ) { ( bytes_push_int out n ) } {}
}

// A float as json_float spells one; NaN and the infinities, which JSON
// cannot, as null.
@ jw_float JsonWriter w ( Vec u ) out f x → v {
    ? ( __jw_value w out ) {
        ? | != 0 ( nurl_is_nan x ) != 0 ( nurl_is_inf x ) { ( bytes_extend_str out `null` ) } {
            ( __json_float_digits out x )
        }
    } {}
}

@ jw_bool JsonWriter w ( Vec u ) out b value → v {
    ? ( __jw_value w out ) { ( bytes_extend_str out ? value `true` `false` ) } {}
}

@ jw_null JsonWriter w ( Vec u ) out → v {
    ? ( __jw_value w out ) { ( bytes_extend_str out `null` ) } {}
}

@ jw_json JsonWriter w ( Vec u ) out Json j → v {
    ? ( __jw_value w out ) { ( __json_emit out j ) } {}
}

@ jw_raw JsonWriter w ( Vec u ) out s json → v {
    ? ( __jw_value w out ) { ( bytes_extend_str out json ) } {}
}

@ jw_raw_slice JsonWriter w ( Vec u ) out ( Slice u ) json → v {
    ? ( __jw_value w out ) { ( bytes_extend_slice out json ) } {}
}

@ jw_ok JsonWriter w → b { ^ & == ( vec_len [u] . w st ) 1 == ( vec_at [u] . w st 0 ) 7 }

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
// `json_obj_each` walks JObj key-value pairs, calling `f` with the key
// (an `s` view, valid during the call) and the JSON value. Both are
// no-ops on a non-matching variant — they don't fail, they just don't
// iterate anything.
//
// `json_obj_keys` returns a fresh `Vec[String]` copy of the keys; the
// caller owns the Vec and each String inside — dropped with it.
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
                                ? < + k 1 n {
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
// new entry): using them after the call is rejected.
//
// Both operations return T on success, F when `j` is the wrong variant
// (the value is then dropped).

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
            // Find the key's slot first, then hand `val` over at exactly
            // one place: the walk proves one owner per path, and a store
            // inside the search loop it could not tell from a second one.
            : ~ i found -1
            : ~ i k 0
            ~ & < found 0 < k n {
                : ?Json ek ( vec_get [Json] v k )
                ?? ek {
                    T jk → {
                        ?? jk {
                            JStr ks → { ? != 0 ( nurl_str_eq ( string_data ks ) key ) { = found k } {} }
                            _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 2
            }
            ? >= found 0 {
                // Key match: the new value replaces the old at slot k+1
                // (vec_set drops the old one); an odd-sized, malformed
                // object gets it appended, restoring the alternating shape.
                : i k_v + found 1
                ? < k_v n { ( vec_set [Json] v k_v val ) } { ( vec_push [Json] v val ) }
            } {
                // No match → append fresh pair.
                ( vec_push [Json] v @ Json { JStr ( string_from key ) } )
                ( vec_push [Json] v val )
            }
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
// The returned Json is lent from inside `j` (releasing it is rejected);
// it goes with `j`.

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
                = seg_start + k 1
            }
        } {}
        = k + k 1
    }
    ? miss { ^ @ ?Json { F @ Json { JNull } } } {}
    ^ @ ?Json { T cur }
}
