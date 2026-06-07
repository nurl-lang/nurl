// stdlib/ext/yaml.nu — a pragmatic YAML parser + serializer
//
// Parses the common YAML subset into the canonical `Json` value from
// stdlib/ext/json.nu (YAML's data model is a superset of JSON's, so every
// `json_*` accessor, `json_free`, and `json_stringify` work unchanged on a
// parsed document) and serializes a `Json` tree back to block-style YAML.
//
// Handled (the pragmatic subset called out in TODO.md):
//   * Block mappings        key: value  /  key:\n  (nested block)
//   * Block sequences       - item      /  -\n      (nested block)
//   * The "sequence under a key at the same indentation" idiom:
//         items:
//         - a
//         - b
//   * Compact nested notation:  - key: val   (list item that is a map)
//   * Scalars: plain, single-quoted ('' escape) and double-quoted
//     (\n \t \r \\ \" \0 \b \f and friends), resolved per the YAML 1.2
//     core schema: null / ~ → JNull; true / false (any case) → JBool;
//     integers and floats → JNum; everything else → JStr.
//   * Flow collections:  [a, b, c]  and  {a: 1, b: 2}  (nesting allowed).
//   * `#` comments to end of line (quote-aware), blank lines, and the
//     `---` / `...` document markers (skipped — single document only).
//
// NOT handled (out of scope; full YAML 1.2 is a large spec):
//   * Block scalars `|` / `>` (literal / folded).
//   * Anchors / aliases (`&a` / `*a`), tags (`!!str`), merge keys (`<<`).
//   * Multiple documents in one stream (only the first is parsed; a `---`
//     separator is treated as a no-op marker).
//   * Complex mapping keys (`? key`), `\xNN` / `\uNNNN` escapes in
//     double-quoted scalars (passed through verbatim), and the YAML 1.1
//     `yes/no/on/off` booleans (kept as strings, by design — the
//     "Norway problem"). Tabs used for indentation are rejected.
//
//   ( yaml_parse src )       → ! Json YamlErr   parse one document
//   ( yaml_stringify j )     → String           serialize (block style)
//   ( yaml_err_name e )      → s                 render an error
//
// Ownership: yaml_parse returns an owned `Json` (free with `json_free`);
// it BORROWS its input. yaml_stringify returns an owned `String` the
// caller frees. Malformed structure (a tab indent, an unterminated flow
// collection, trailing un-indented junk) is reported via `YamlErr`;
// malformed block-level quoted scalars are handled leniently (the raw
// text is kept) rather than failing the whole parse.

$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: | YamlErr { YamlSyntax YamlBadIndent YamlUnterminated YamlOther }

@ yaml_err_name YamlErr e → s {
    ^ ?? e {
        YamlSyntax → `YamlSyntax`
        YamlBadIndent → `YamlBadIndent`
        YamlUnterminated → `YamlUnterminated`
        YamlOther → `YamlOther`
    }
}

@ __yaml_errcode i code → YamlErr {
    ? == code 2 { ^ @ YamlErr { YamlBadIndent } } {}
    ? == code 3 { ^ @ YamlErr { YamlUnterminated } } {}
    ? == code 1 { ^ @ YamlErr { YamlSyntax } } {}
    ^ @ YamlErr { YamlOther }
}

// ── A normalized source line ──────────────────────────────────────────
// `indent` = leading-space count; `text` = the content after the
// indentation, with any trailing comment stripped and right-trimmed.
: YamlLine { i indent  String text }

// Recursive-descent state over the normalized lines. `err` is set
// (non-zero YamlErr code) when a nested scalar fails (e.g. a malformed
// flow collection) so the whole parse fails rather than degrading.
: YamlParser { ( Vec YamlLine ) lines  i count  i cur  i err }

// ── Small char / byte helpers ─────────────────────────────────────────

@ __yaml_is_sp i c → b { ^ | == c 32 == c 9 }
@ __yaml_is_digit i c → b { ^ & >= c 48 <= c 57 }
@ __yaml_is_e i c → b { ^ | == c 101 == c 69 }
@ __yaml_is_sign i c → b { ^ | == c 43 == c 45 }

@ __yaml_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// O(1) byte read against a raw `s` buffer (no per-call strlen).
@ __yaml_src_byte s src i k i n → i {
    ? | < k 0 >= k n { ^ -1 } {}
    : *u bp # *u src
    ^ & 255 # i . bp k
}

// Bytes [start, start+len) of `src` → owned String (one memcpy).
@ __yaml_substr s src i start i len → String {
    ? <= len 0 { ^ ( string_new ) } {}
    : *u bp # *u src
    : *u from # *u + # i bp start
    ^ ( string_from_bytes_packed from len )
}

@ __yaml_skip_sp s text i pos i n → i {
    : ~ i k pos
    ~ & < k n ( __yaml_is_sp ( nurl_str_get text k ) ) { = k + k 1 }
    ^ k
}

// Case-insensitive ASCII string equality.
@ __yaml_eq_ci s a s b → b {
    : i na ( nurl_str_len a )
    : i nb ( nurl_str_len b )
    ? != na nb { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k na {
        : i ca ( __yaml_lower ( nurl_str_get a k ) )
        : i cb ( __yaml_lower ( nurl_str_get b k ) )
        ? != ca cb { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Return a fresh String == s with trailing spaces/tabs removed.
@ __yaml_rtrim String s → String {
    : s raw ( string_data s )
    : i n ( string_len s )
    : ~ i e n
    : ~ b t T
    ~ & t > e 0 {
        : i c ( nurl_str_get raw - e 1 )
        ? | == c 32 == c 9 { = e - e 1 } { = t F }
    }
    ^ ( __yaml_substr raw 0 e )
}

// True for a number literal (int / float, optional sign + exponent).
@ __yaml_is_number s text → b {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    : i c0 ( nurl_str_get text 0 )
    ? ( __yaml_is_sign c0 ) { = k 1 } {}
    : ~ i digits 0
    ~ & < k n ( __yaml_is_digit ( nurl_str_get text k ) ) { = k + k 1  = digits + digits 1 }
    ? & < k n == ( nurl_str_get text k ) 46 {
        = k + k 1
        ~ & < k n ( __yaml_is_digit ( nurl_str_get text k ) ) { = k + k 1  = digits + digits 1 }
    } {}
    ? == digits 0 { ^ F } {}
    ? & < k n ( __yaml_is_e ( nurl_str_get text k ) ) {
        = k + k 1
        ? & < k n ( __yaml_is_sign ( nurl_str_get text k ) ) { = k + k 1 } {}
        : ~ i ed 0
        ~ & < k n ( __yaml_is_digit ( nurl_str_get text k ) ) { = k + k 1  = ed + ed 1 }
        ? == ed 0 { ^ F } {}
    } {}
    ^ == k n
}

// ── Line normalization ────────────────────────────────────────────────

// Index where content ends (a comment begins, or n). Quote-aware: a `#`
// only opens a comment at line start or after a space/tab, and never
// inside a single- or double-quoted run.
@ __yaml_content_end s raw i start i n → i {
    : ~ i k start
    : ~ b insq F
    : ~ b indq F
    : ~ i res n
    : ~ b done F
    ~ & ! done < k n {
        : i c ( nurl_str_get raw k )
        ? insq {
            ? == c 39 { = insq F } {}
        } {
            ? indq {
                ? == c 34 { = indq F } {
                    ? == c 92 { = k + k 1 } {}
                }
            } {
                ? == c 39 { = insq T } {
                ? == c 34 { = indq T } {
                ? == c 35 {
                    : b atstart == k start
                    : i prev ( nurl_str_get raw - k 1 )
                    : b aftersp | == prev 32 == prev 9
                    ? | atstart aftersp { = res k  = done T } {}
                } {} }
                }
            }
        }
        = k + k 1
    }
    ^ res
}

// Normalize one physical line (no trailing newline) and, if it carries
// content, push a YamlLine to `out`. Returns an error code (0 ok, 2 bad
// indent on a tab) — blank / comment / document-marker lines push nothing.
@ __yaml_process_line String line ( Vec YamlLine ) out → i {
    : s raw ( string_data line )
    : i n ( string_len line )
    : ~ i ind 0
    ~ & < ind n == ( nurl_str_get raw ind ) 32 { = ind + ind 1 }
    ? & < ind n == ( nurl_str_get raw ind ) 9 {
        : i probe ( __yaml_skip_sp raw ind n )
        ? >= probe n { ^ 0 } {}
        ? == ( nurl_str_get raw probe ) 35 { ^ 0 } {}
        ^ 2
    } {}
    : i cend ( __yaml_content_end raw ind n )
    : ~ i e cend
    : ~ b trimming T
    ~ & trimming > e ind {
        : i ch ( nurl_str_get raw - e 1 )
        ? | == ch 32 == ch 9 { = e - e 1 } { = trimming F }
    }
    : i clen - e ind
    ? <= clen 0 { ^ 0 } {}
    : String text ( __yaml_substr raw ind clen )
    : s traw ( string_data text )
    ? | == 1 ( nurl_str_eq traw `---` ) == 1 ( nurl_str_eq traw `...` ) {
        ( string_free text )
        ^ 0
    } {}
    ( vec_push [YamlLine] out @ YamlLine { ind text } )
    ^ 0
}

@ __yaml_split_lines s src ( Vec YamlLine ) out → i {
    : i n ( nurl_str_len src )
    : ~ i i 0
    : ~ i err 0
    ~ < i n {
        : ~ i j i
        ~ & < j n != ( __yaml_src_byte src j n ) 10 { = j + j 1 }
        : i rawlen - j i
        : ~ i ll rawlen
        ? & > ll 0 == ( __yaml_src_byte src + i - ll 1 n ) 13 { = ll - ll 1 } {}
        : String line ( __yaml_substr src i ll )
        : i lerr ( __yaml_process_line line out )
        ? & == err 0 != lerr 0 { = err lerr } {}
        ( string_free line )
        = i + j 1
    }
    ^ err
}

@ __yaml_free_lines ( Vec YamlLine ) lines → v {
    ( vec_free_with [YamlLine] lines \ YamlLine l → v { ( string_free . l text ) } )
}

// ── Quoted-scalar scanners (shared by block + flow) ───────────────────

: __YStr { String str  i pos  b ok }

@ __yaml_dq_escape String out i e → v {
    ? == e 110 { ( string_push_char out 10 ) } {       // n
    ? == e 116 { ( string_push_char out 9 ) } {        // t
    ? == e 114 { ( string_push_char out 13 ) } {       // r
    ? == e 48  { ( string_push_char out 0 ) } {        // 0
    ? == e 92  { ( string_push_char out 92 ) } {       // backslash
    ? == e 34  { ( string_push_char out 34 ) } {       // "
    ? == e 47  { ( string_push_char out 47 ) } {       // /
    ? == e 98  { ( string_push_char out 8 ) } {        // b
    ? == e 102 { ( string_push_char out 12 ) } {       // f
        ( string_push_char out e )                     // unknown: literal
    } } } } } } } } }
}

// text[pos] == '"' ; returns content + index after the closing quote.
@ __yaml_scan_dquote s text i n i pos → __YStr {
    : String out ( string_new )
    : ~ i k + pos 1
    : ~ b done F
    : ~ b ok F
    ~ & ! done < k n {
        : i c ( nurl_str_get text k )
        ? == c 34 { = done T  = ok T  = k + k 1 } {
            ? == c 92 {
                = k + k 1
                ? >= k n { = done T } {
                    ( __yaml_dq_escape out ( nurl_str_get text k ) )
                    = k + k 1
                }
            } {
                ( string_push_char out c )
                = k + k 1
            }
        }
    }
    ^ @ __YStr { out k ok }
}

// text[pos] == '\'' ; '' is an escaped single quote.
@ __yaml_scan_squote s text i n i pos → __YStr {
    : String out ( string_new )
    : ~ i k + pos 1
    : ~ b done F
    : ~ b ok F
    ~ & ! done < k n {
        : i c ( nurl_str_get text k )
        ? == c 39 {
            : i nx ( nurl_str_get text + k 1 )
            ? & < + k 1 n == nx 39 {
                ( string_push_char out 39 )
                = k + k 2
            } {
                = done T  = ok T  = k + k 1
            }
        } {
            ( string_push_char out c )
            = k + k 1
        }
    }
    ^ @ __YStr { out k ok }
}

// ── Plain-scalar resolution (YAML 1.2 core schema) ────────────────────

@ __yaml_resolve_plain s text → Json {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ @ Json { JNull } } {}
    ? ( __yaml_eq_ci text `null` ) { ^ @ Json { JNull } } {}
    ? == 1 ( nurl_str_eq text `~` ) { ^ @ Json { JNull } } {}
    ? ( __yaml_eq_ci text `true` ) { ^ @ Json { JBool T } } {}
    ? ( __yaml_eq_ci text `false` ) { ^ @ Json { JBool F } } {}
    ? ( __yaml_is_number text ) { ^ @ Json { JNum ( string_from text ) } } {}
    ^ @ Json { JStr ( string_from text ) }
}

// Resolve a complete scalar token (the value text after a `:` or `-`,
// or a flow element): dispatch quoted / flow / plain. `p` carries the
// error flag so a malformed flow collection fails the whole parse
// rather than degrading to a string. Block-level quoted scalars stay
// lenient (an unterminated quote keeps the raw text).
@ __yaml_scalar_to_json * YamlParser p s text → Json {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ @ Json { JNull } } {}
    : i c0 ( nurl_str_get text 0 )
    ? == c0 34 {
        : __YStr r ( __yaml_scan_dquote text n 0 )
        ? . r ok { ^ @ Json { JStr . r str } } {}
        ( string_free . r str )
        ^ @ Json { JStr ( string_from text ) }
    } {}
    ? == c0 39 {
        : __YStr r ( __yaml_scan_squote text n 0 )
        ? . r ok { ^ @ Json { JStr . r str } } {}
        ( string_free . r str )
        ^ @ Json { JStr ( string_from text ) }
    } {}
    ? | == c0 91 == c0 123 {
        : !Json YamlErr fr ( __yaml_parse_flow text )
        ^ ?? fr {
            T j → j
            F _ → { = . p err 1  ^ @ Json { JNull } }
        }
    } {}
    ^ ( __yaml_resolve_plain text )
}

// ── Flow collections ([..] / {..]}) ───────────────────────────────────

: __YFlow { Json val  i pos  b ok }

@ __yaml_flow_plain_end s text i n i pos b stop_colon → i {
    : ~ i k pos
    : ~ b done F
    ~ & ! done < k n {
        : i c ( nurl_str_get text k )
        ? | | == c 44 == c 93 == c 125 { = done T } {
            ? & stop_colon == c 58 {
                : i nx ( nurl_str_get text + k 1 )
                : b atend == + k 1 n
                : b sep | | atend == nx 32 == nx 9
                ? sep { = done T } { = k + k 1 }
            } { = k + k 1 }
        }
    }
    ^ k
}

@ __yaml_flow_scalar s text i n i pos b stop_colon → __YFlow {
    : i c ( nurl_str_get text pos )
    ? == c 34 {
        : __YStr r ( __yaml_scan_dquote text n pos )
        ^ @ __YFlow { @ Json { JStr . r str } . r pos . r ok }
    } {}
    ? == c 39 {
        : __YStr r ( __yaml_scan_squote text n pos )
        ^ @ __YFlow { @ Json { JStr . r str } . r pos . r ok }
    } {}
    : i e ( __yaml_flow_plain_end text n pos stop_colon )
    : String raw ( __yaml_substr text pos - e pos )
    : String tr ( __yaml_rtrim raw )
    ( string_free raw )
    : Json j ( __yaml_resolve_plain ( string_data tr ) )
    ( string_free tr )
    ^ @ __YFlow { j e T }
}

@ __yaml_json_as_key Json j → String {
    ^ ?? j {
        JStr s → ( string_from ( string_data s ) )
        JNum s → ( string_from ( string_data s ) )
        JBool b → ( string_from ? b `true` `false` )
        JNull → ( string_from `null` )
        _ → ( string_new )
    }
}

@ __yaml_flow_value s text i n i pos → __YFlow {
    : i p ( __yaml_skip_sp text pos n )
    ? >= p n { ^ @ __YFlow { @ Json { JNull } p F } } {}
    : i c ( nurl_str_get text p )
    ? == c 91 { ^ ( __yaml_flow_seq text n p ) } {}
    ? == c 123 { ^ ( __yaml_flow_map text n p ) } {}
    ^ ( __yaml_flow_scalar text n p F )
}

@ __yaml_flow_seq s text i n i pos → __YFlow {
    : Json arr ( json_arr_new )
    : ~ i p + pos 1
    : ~ b done F
    : ~ b ok T
    = p ( __yaml_skip_sp text p n )
    ? & < p n == ( nurl_str_get text p ) 93 { ^ @ __YFlow { arr + p 1 T } } {}
    ~ & ! done ok {
        : __YFlow ev ( __yaml_flow_value text n p )
        ? ! . ev ok { = ok F  = done T  ( json_free . ev val ) } {
            ( json_arr_push arr . ev val )
            = p ( __yaml_skip_sp text . ev pos n )
            ? >= p n { = ok F  = done T } {
                : i c ( nurl_str_get text p )
                ? == c 44 { = p ( __yaml_skip_sp text + p 1 n ) } {
                    ? == c 93 { = p + p 1  = done T } {
                        = ok F  = done T
                    }
                }
            }
        }
    }
    ^ @ __YFlow { arr p ok }
}

@ __yaml_flow_map s text i n i pos → __YFlow {
    : Json obj ( json_obj_new )
    : ~ i p + pos 1
    : ~ b done F
    : ~ b ok T
    = p ( __yaml_skip_sp text p n )
    ? & < p n == ( nurl_str_get text p ) 125 { ^ @ __YFlow { obj + p 1 T } } {}
    ~ & ! done ok {
        = p ( __yaml_skip_sp text p n )
        : __YFlow kv ( __yaml_flow_scalar text n p T )
        ? ! . kv ok { = ok F  = done T  ( json_free . kv val ) } {
            : String keystr ( __yaml_json_as_key . kv val )
            ( json_free . kv val )
            = p ( __yaml_skip_sp text . kv pos n )
            : b nocolon | >= p n != ( nurl_str_get text p ) 58
            ? nocolon { = ok F  = done T  ( string_free keystr ) } {
                = p ( __yaml_skip_sp text + p 1 n )
                : __YFlow vv ( __yaml_flow_value text n p )
                ? ! . vv ok { = ok F  = done T  ( string_free keystr )  ( json_free . vv val ) } {
                    ( json_obj_set obj ( string_data keystr ) . vv val )
                    ( string_free keystr )
                    = p ( __yaml_skip_sp text . vv pos n )
                    ? >= p n { = ok F  = done T } {
                        : i c ( nurl_str_get text p )
                        ? == c 44 { = p + p 1 } {
                            ? == c 125 { = p + p 1  = done T } {
                                = ok F  = done T
                            }
                        }
                    }
                }
            }
        }
    }
    ^ @ __YFlow { obj p ok }
}

// Parse a flow collection that spans the whole `text` (leading char is
// '[' or '{'). Trailing content after the close is ignored (lenient).
@ __yaml_parse_flow s text → !Json YamlErr {
    : i n ( nurl_str_len text )
    : __YFlow r ( __yaml_flow_value text n 0 )
    ? . r ok { ^ @ !Json YamlErr { T . r val } } {}
    ( json_free . r val )
    ^ @ !Json YamlErr { F @ YamlErr { YamlSyntax } }
}

// ── Block parser (indentation-driven, over normalized lines) ──────────

@ __yp_new ( Vec YamlLine ) lines → *YamlParser {
    : *YamlParser p # *YamlParser ( nurl_alloc Z YamlParser )
    = . p lines lines
    = . p count ( vec_len [YamlLine] lines )
    = . p cur 0
    = . p err 0
    ^ p
}

@ __yp_indent_at * YamlParser p i idx → i {
    ? | < idx 0 >= idx . p count { ^ -1 } {}
    : ?YamlLine lo ( vec_get [YamlLine] . p lines idx )
    ^ ?? lo { T l → . l indent  F → -1 }
}

@ __yp_text_at * YamlParser p i idx → s {
    ? | < idx 0 >= idx . p count { ^ `` } {}
    : ?YamlLine lo ( vec_get [YamlLine] . p lines idx )
    ^ ?? lo { T l → ( string_data . l text )  F → `` }
}

// Replace line `idx` with (newind, newtext); frees the old text.
@ __yp_rewrite_line * YamlParser p i idx i newind String newtext → v {
    : ?YamlLine lo ( vec_get [YamlLine] . p lines idx )
    ?? lo {
        T l → {
            ( string_free . l text )
            ( vec_set [YamlLine] . p lines idx @ YamlLine { newind newtext } )
        }
        F → ( string_free newtext )
    }
}

@ __yaml_is_seq_item s text → b {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ F } {}
    ? != ( nurl_str_get text 0 ) 45 { ^ F } {}
    ? == n 1 { ^ T } {}
    : i c ( nurl_str_get text 1 )
    ^ | == c 32 == c 9
}

// Index of the key/value `:` (followed by space or end), at flow depth 0
// and outside quotes; -1 if none → the line is not a block map entry.
@ __yaml_find_kv_colon s text → i {
    : i n ( nurl_str_len text )
    : ~ i k 0
    : ~ b insq F
    : ~ b indq F
    : ~ i depth 0
    : ~ i res -1
    : ~ b done F
    ~ & ! done < k n {
        : i c ( nurl_str_get text k )
        ? insq {
            ? == c 39 { = insq F } {}
        } {
            ? indq {
                ? == c 34 { = indq F } {
                    ? == c 92 { = k + k 1 } {}
                }
            } {
                ? == c 39 { = insq T } {
                ? == c 34 { = indq T } {
                ? | == c 91 == c 123 { = depth + depth 1 } {
                ? | == c 93 == c 125 { = depth - depth 1 } {
                ? & == c 58 == depth 0 {
                    : i nx ( nurl_str_get text + k 1 )
                    : b atend == + k 1 n
                    : b spc | == nx 32 == nx 9
                    ? | atend spc { = res k  = done T } {}
                } {} } } } }
            }
        }
        = k + k 1
    }
    ^ res
}

@ __yaml_parse_node * YamlParser p i min_indent → Json {
    : i idx . p cur
    ? >= idx . p count { ^ @ Json { JNull } } {}
    : i ind ( __yp_indent_at p idx )
    ? < ind min_indent { ^ @ Json { JNull } } {}
    : s text ( __yp_text_at p idx )
    ? ( __yaml_is_seq_item text ) { ^ ( __yaml_parse_seq p ind ) } {}
    ? >= ( __yaml_find_kv_colon text ) 0 { ^ ( __yaml_parse_map p ind ) } {}
    = . p cur + . p cur 1
    ^ ( __yaml_scalar_to_json p text )
}

@ __yaml_parse_map * YamlParser p i ind → Json {
    : Json obj ( json_obj_new )
    : ~ b more T
    ~ more {
        : i idx . p cur
        ? >= idx . p count { = more F } {
            : i lind ( __yp_indent_at p idx )
            ? != lind ind { = more F } {
                : s text ( __yp_text_at p idx )
                : i col ( __yaml_find_kv_colon text )
                ? < col 0 { = more F } {
                    : i tn ( nurl_str_len text )
                    : String keyraw ( __yaml_substr text 0 col )
                    : Json keyj ( __yaml_scalar_to_json p ( string_data keyraw ) )
                    ( string_free keyraw )
                    : String key ( __yaml_json_as_key keyj )
                    ( json_free keyj )
                    : i rstart ( __yaml_skip_sp text + col 1 tn )
                    = . p cur + . p cur 1
                    : Json val @ Json { JNull }
                    ? < rstart tn {
                        : String rests ( __yaml_substr text rstart - tn rstart )
                        = val ( __yaml_scalar_to_json p ( string_data rests ) )
                        ( string_free rests )
                    } {
                        : i nind ( __yp_indent_at p . p cur )
                        : s ntext ( __yp_text_at p . p cur )
                        : b seqsame & == nind ind ( __yaml_is_seq_item ntext )
                        ? seqsame { = val ( __yaml_parse_seq p ind ) } { = val ( __yaml_parse_node p + ind 1 ) }
                    }
                    ( json_obj_set obj ( string_data key ) val )
                    ( string_free key )
                }
            }
        }
    }
    ^ obj
}

@ __yaml_parse_seq * YamlParser p i ind → Json {
    : Json arr ( json_arr_new )
    : ~ b more T
    ~ more {
        : i idx . p cur
        ? >= idx . p count { = more F } {
            : i lind ( __yp_indent_at p idx )
            ? != lind ind { = more F } {
                : s text ( __yp_text_at p idx )
                ? ! ( __yaml_is_seq_item text ) { = more F } {
                    : i tn ( nurl_str_len text )
                    : i after ( __yaml_skip_sp text 1 tn )
                    : Json item @ Json { JNull }
                    ? >= after tn {
                        = . p cur + . p cur 1
                        = item ( __yaml_parse_node p + ind 1 )
                    } {
                        : i ccol + ind after
                        : String rest ( __yaml_substr text after - tn after )
                        ( __yp_rewrite_line p idx ccol rest )
                        = item ( __yaml_parse_node p ccol )
                    }
                    ( json_arr_push arr item )
                }
            }
        }
    }
    ^ arr
}

@ yaml_parse s src → !Json YamlErr {
    : ( Vec YamlLine ) lines ( vec_new [YamlLine] )
    : i splerr ( __yaml_split_lines src lines )
    ? != splerr 0 {
        ( __yaml_free_lines lines )
        ^ @ !Json YamlErr { F ( __yaml_errcode splerr ) }
    } {}
    : i nlines ( vec_len [YamlLine] lines )
    ? == nlines 0 {
        ( __yaml_free_lines lines )
        ^ @ !Json YamlErr { T @ Json { JNull } }
    } {}
    : *YamlParser p ( __yp_new lines )
    : Json root ( __yaml_parse_node p 0 )
    : i consumed . p cur
    : i perr . p err
    ( nurl_free # s p )
    ( __yaml_free_lines lines )
    ? | != perr 0 < consumed nlines {
        ( json_free root )
        ^ @ !Json YamlErr { F @ YamlErr { YamlSyntax } }
    } {}
    ^ @ !Json YamlErr { T root }
}

// ── Serializer (block style) ──────────────────────────────────────────

@ __yaml_indent String out i n → v {
    : ~ i k 0
    ~ < k n { ( string_push_char out 32 )  = k + k 1 }
}

@ __yaml_is_indicator i c → b {
    ? == c 45 { ^ T } {}    // -
    ? == c 63 { ^ T } {}    // ?
    ? == c 58 { ^ T } {}    // :
    ? == c 44 { ^ T } {}    // ,
    ? == c 91 { ^ T } {}    // [
    ? == c 93 { ^ T } {}    // ]
    ? == c 123 { ^ T } {}   // {
    ? == c 125 { ^ T } {}   // }
    ? == c 35 { ^ T } {}    // #
    ? == c 38 { ^ T } {}    // &
    ? == c 42 { ^ T } {}    // *
    ? == c 33 { ^ T } {}    // !
    ? == c 124 { ^ T } {}   // |
    ? == c 62 { ^ T } {}    // >
    ? == c 39 { ^ T } {}    // '
    ? == c 34 { ^ T } {}    // "
    ? == c 37 { ^ T } {}    // %
    ? == c 64 { ^ T } {}    // @
    ? == c 96 { ^ T } {}    // `
    ^ F
}

// True when `raw` can be emitted as a bare plain scalar and read back as
// the identical string (no quoting needed).
@ __yaml_plain_safe s raw → b {
    : i n ( nurl_str_len raw )
    ? == n 0 { ^ F } {}
    : i c0 ( nurl_str_get raw 0 )
    ? ( __yaml_is_indicator c0 ) { ^ F } {}
    : i clast ( nurl_str_get raw - n 1 )
    ? | | | == c0 32 == clast 32 == c0 9 == clast 9 { ^ F } {}
    : ~ i k 0
    : ~ b safe T
    ~ & safe < k n {
        : i c ( nurl_str_get raw k )
        ? | == c 10 == c 9 { = safe F } {
            ? == c 58 {
                : i nx ( nurl_str_get raw + k 1 )
                : b atend == + k 1 n
                ? | atend | == nx 32 == nx 9 { = safe F } {}
            } {
                ? == c 35 {
                    : i pv ( nurl_str_get raw - k 1 )
                    ? | == pv 32 == pv 9 { = safe F } {}
                } {}
            }
        }
        = k + k 1
    }
    ? ! safe { ^ F } {}
    ? ( __yaml_eq_ci raw `null` ) { ^ F } {}
    ? == 1 ( nurl_str_eq raw `~` ) { ^ F } {}
    ? ( __yaml_eq_ci raw `true` ) { ^ F } {}
    ? ( __yaml_eq_ci raw `false` ) { ^ F } {}
    ? ( __yaml_is_number raw ) { ^ F } {}
    ^ T
}

@ __yaml_emit_dquoted String out s raw → v {
    ( string_push_char out 34 )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        ? == c 34 { ( string_push_char out 92 ) ( string_push_char out 34 ) } {
            ? == c 92 { ( string_push_char out 92 ) ( string_push_char out 92 ) } {
                ? == c 10 { ( string_push_char out 92 ) ( string_push_char out 110 ) } {
                    ? == c 9 { ( string_push_char out 92 ) ( string_push_char out 116 ) } {
                        ? == c 13 { ( string_push_char out 92 ) ( string_push_char out 114 ) } {
                            ( string_push_char out c )
                        } } } } }
        = k + k 1
    }
    ( string_push_char out 34 )
}

@ __yaml_render_string String out s raw → v {
    ? ( __yaml_plain_safe raw ) { ( string_push_str out raw ) } { ( __yaml_emit_dquoted out raw ) }
}

@ __yaml_render_scalar String out Json j → v {
    ?? j {
        JNull → ( string_push_str out `null` )
        JBool b → ( string_push_str out ? b `true` `false` )
        JNum s → ( string_push_str out ( string_data s ) )
        JStr s → ( __yaml_render_string out ( string_data s ) )
        _ → {}
    }
}

// Emit the right-hand side of a `key:` or `-`: ` scalar\n`, ` []`/` {}`
// for empties, or `\n` + a nested block at `child`.
@ __yaml_emit_valpart String out Json val i child → v {
    ?? val {
        JArr v → {
            ? == 0 ( vec_len [Json] v ) { ( string_push_str out ` []` ) ( string_push_char out 10 ) } {
                ( string_push_char out 10 )
                ( __yaml_emit_seq out v child )
            }
        }
        JObj v → {
            ? == 0 ( vec_len [Json] v ) { ( string_push_str out ` {}` ) ( string_push_char out 10 ) } {
                ( string_push_char out 10 )
                ( __yaml_emit_map out v child )
            }
        }
        _ → {
            ( string_push_char out 32 )
            ( __yaml_render_scalar out val )
            ( string_push_char out 10 )
        }
    }
}

@ __yaml_emit_map String out ( Vec Json ) v i indent → v {
    : i n ( vec_len [Json] v )
    : ~ i k 0
    ~ < k n {
        ( __yaml_indent out indent )
        : ?Json ek ( vec_get [Json] v k )
        ?? ek { T jk → ( __yaml_render_scalar out jk )  F → {} }
        ( string_push_char out 58 )
        ? < + k 1 n {
            : ?Json ev ( vec_get [Json] v + k 1 )
            ?? ev { T jv → ( __yaml_emit_valpart out jv + indent 2 )  F → ( string_push_char out 10 ) }
        } {
            ( string_push_char out 10 )
        }
        = k + k 2
    }
}

@ __yaml_emit_seq String out ( Vec Json ) v i indent → v {
    : i n ( vec_len [Json] v )
    : ~ i k 0
    ~ < k n {
        ( __yaml_indent out indent )
        ( string_push_char out 45 )
        : ?Json e ( vec_get [Json] v k )
        ?? e { T jv → ( __yaml_emit_valpart out jv + indent 2 )  F → ( string_push_char out 10 ) }
        = k + k 1
    }
}

@ __yaml_emit_node String out Json j i indent → v {
    ?? j {
        JArr v → {
            ? == 0 ( vec_len [Json] v ) { ( __yaml_indent out indent ) ( string_push_str out `[]` ) ( string_push_char out 10 ) } { ( __yaml_emit_seq out v indent ) }
        }
        JObj v → {
            ? == 0 ( vec_len [Json] v ) { ( __yaml_indent out indent ) ( string_push_str out `{}` ) ( string_push_char out 10 ) } { ( __yaml_emit_map out v indent ) }
        }
        _ → {
            ( __yaml_indent out indent )
            ( __yaml_render_scalar out j )
            ( string_push_char out 10 )
        }
    }
}

@ yaml_stringify Json j → String {
    : String out ( string_new )
    ( __yaml_emit_node out j 0 )
    ^ out
}
