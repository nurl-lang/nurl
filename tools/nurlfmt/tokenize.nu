// tools/nurlfmt/tokenize.nu — formatter-friendly tokeniser.
//
// nurlc.nu's tokeniser drops comments and inter-token whitespace,
// both of which the formatter needs. This module re-tokenises NURL
// source from scratch onto a Vec[FmtTok], where each token carries:
//
//   kind       — TT_FMT_* discriminant (see below)
//   text       — exact source slice (owned)
//   nl_before  — count of source newlines between the previous token
//                and this one (0 = same line, 1 = next line, ≥2 =
//                blank line in between, clamped to 2 for the
//                formatter's purposes)
//
// Token kinds are deliberately coarse: the formatter does not need
// to enforce arity, so single-/multi-char operators and type
// keywords collapse onto TT_FMT_OP / TT_FMT_IDENT respectively. The
// canonical layout is derived from token text + brace/paren depth +
// nl_before, not from a parse tree.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Token kinds ─────────────────────────────────────────────────
: i TT_FMT_IDENT 1  // identifier, type keyword, T/F bool, ::-merged
: i TT_FMT_INT 2  // decimal integer (possibly leading '-')
: i TT_FMT_FLOAT 3  // decimal float   (possibly leading '-')
: i TT_FMT_STR 4  // `...` backtick string (text includes the backticks)
: i TT_FMT_OP 5  // any operator / punctuation token (single- or multi-char)
: i TT_FMT_COMMENT 6  // // ... line comment (text includes the leading //)
: i TT_FMT_EOF 7  // sentinel; emitted exactly once at end of stream

: FmtTok {
    i kind
    s text
    i nl_before
}

// ── Byte-class predicates ──────────────────────────────────────
// ASCII-only. NURL source files are UTF-8 but identifiers, numbers
// and operators live in the ASCII subset; the only non-ASCII glyph
// the grammar recognises is `→` (U+2192 → 0xE2 0x86 0x92), which
// the tokeniser detects by raw byte sequence.

@ fmt_is_digit i c → b {
    ^ & >= c 48 <= c 57
}

@ fmt_is_alpha i c → b {
    ^ | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ fmt_is_ident_start i c → b {
    ^ | ( fmt_is_alpha c ) == c 95
}

@ fmt_is_ident_cont i c → b {
    ^ | | ( fmt_is_alpha c ) ( fmt_is_digit c ) == c 95
}

// Whitelist of single-byte operator/punctuation chars from
// grammar v1.8. Falls back to a best-effort single-byte OP token
// for anything not in this list, so the formatter degrades
// gracefully on syntax it does not yet recognise.
@ fmt_is_op_byte i c → b {
    ? == c 64 { ^ T } {}  // @
    ? == c 58 { ^ T } {}  // :
    ? == c 61 { ^ T } {}  // =
    ? == c 94 { ^ T } {}  // ^
    ? == c 63 { ^ T } {}  // ?
    ? == c 126 { ^ T } {}  // ~
    ? == c 40 { ^ T } {}  // (
    ? == c 41 { ^ T } {}  // )
    ? == c 123 { ^ T } {}  // {
    ? == c 125 { ^ T } {}  // }
    ? == c 46 { ^ T } {}  // .
    ? == c 35 { ^ T } {}  // #
    ? == c 33 { ^ T } {}  // !
    ? == c 43 { ^ T } {}  // +
    ? == c 45 { ^ T } {}  // -
    ? == c 42 { ^ T } {}  // *
    ? == c 47 { ^ T } {}  // /
    ? == c 37 { ^ T } {}  // %
    ? == c 38 { ^ T } {}  // &
    ? == c 124 { ^ T } {}  // |
    ? == c 60 { ^ T } {}  // <
    ? == c 62 { ^ T } {}  // >
    ? == c 91 { ^ T } {}  // [
    ? == c 93 { ^ T } {}  // ]
    ? == c 92 { ^ T } {}  // \
    ? == c 36 { ^ T } {}  // $
    ? == c 59 { ^ T } {}  // ;
    ? == c 90 { ^ T } {}  // Z (sizeof)
    ^ F
}

// ── Token emission ─────────────────────────────────────────────
// Centralised helper so callers only manage the source-window
// [start, end) and the kind. The `text` slice is constructed
// inline in the struct literal so the compiler does NOT bind it
// to a local: a named owned binding would be auto-dropped at the
// helper's scope exit, leaving a dangling pointer in the Vec.
// Instead the Vec's elements hold the only reference; cleanup is
// the caller's responsibility (see tokens_free).
@ __fmt_emit ( Vec FmtTok ) toks s src i start i end i kind i nl_acc → v {
    : i nl_clamped ? > nl_acc 2 2 nl_acc
    ( vec_push [FmtTok] toks
    @ FmtTok { kind ( nurl_str_slice src start - end start ) nl_clamped } )
}

// Match a UTF-8 `→` (E2 86 92) at index i. Out-of-range slots read
// as 0 from nurl_str_get so the bounds check is implicit.
@ __fmt_is_arrow s src i i → b {
    & == 226 ( nurl_str_get src i )
    & == 134 ( nurl_str_get src + i 1 )
    == 146 ( nurl_str_get src + i 2 )
}

// ── Main tokenise driver ───────────────────────────────────────
// Returns an owned Vec[FmtTok] ending with one TT_FMT_EOF entry.
// Caller is responsible for releasing it via tokens_free.
@ tokenize s src → ( Vec FmtTok ) {
    : ( Vec FmtTok ) toks ( vec_with_cap [FmtTok] 256 )
    : i n ( nurl_str_len src )
    : ~ i i 0
    : ~ i nl_acc 0

    ~ < i n {
        : i c ( nurl_str_get src i )
        : i c2 ( nurl_str_get src + i 1 )

        // 1) Whitespace: space / tab / CR are skipped silently.
        //    LF bumps the newline accumulator for the next emitted token.
        ? | | == c 32 == c 9 == c 13 {
            = i + i 1
        } {}
        ? == c 10 {
            = nl_acc + nl_acc 1
            = i + i 1
        } {}

        // Bail to the next iteration if whitespace consumed `c` — re-fetch
        // the current byte first. (NURL has no `continue`; the predicate
        // below short-circuits any further work for this i.)
        ? & < i n & != c 32 & != c 9 & != c 13 != c 10 {

            // 2) Line comment `// ... up to LF`
            ? & == c 47 == c2 47 {
                : ~ i j + i 2
                ~ & < j n != ( nurl_str_get src j ) 10 {
                    = j + j 1
                }
                ( __fmt_emit toks src i j TT_FMT_COMMENT nl_acc )
                = nl_acc 0
                = i j
            } {

                // 3) Backtick string with \X escapes.
                //    Match the runtime lexer (stdlib/runtime.c §lex_next):
                //    a backslash advances TWO bytes ONLY when followed by
                //    one of n / t / r / \. For any other `\X` pair the
                //    backslash itself is a raw byte (grammar §LEXICAL: "any
                //    other \X is passed through verbatim"), which means the
                //    following byte CAN be the closing backtick (e.g. the
                //    literal `\` on its own — backslash, then end of
                //    string).
                ? == c 96 {
                    : ~ i j + i 1
                    : ~ b done F
                    ~ ! done {
                        ? >= j n {
                            = done T
                        } {
                            : i ch ( nurl_str_get src j )
                            ? & == ch 92 < + j 1 n {
                                : i nx ( nurl_str_get src + j 1 )
                                ? | | | == nx 110 == nx 116 == nx 114 == nx 92 {
                                    = j + j 2
                                } {
                                    = j + j 1
                                }
                            } {
                                ? == ch 96 {
                                    = j + j 1
                                    = done T
                                } {
                                    = j + j 1
                                } }
                        }
                    }
                    ( __fmt_emit toks src i j TT_FMT_STR nl_acc )
                    = nl_acc 0
                    = i j
                } {

                    // 4) Numeric literal: digit, or `-` immediately followed by digit
                    ? | ( fmt_is_digit c )
                    & == c 45 ( fmt_is_digit c2 )
                    {
                        : ~ i j i
                        ? == c 45 {
                            = j + j 1
                        } {}
                        ~ & < j n ( fmt_is_digit ( nurl_str_get src j ) ) {
                            = j + j 1
                        }
                        : ~ i kind TT_FMT_INT
                        // FLOAT requires `.` followed by another digit.
                        ? & == ( nurl_str_get src j ) 46
                        ( fmt_is_digit ( nurl_str_get src + j 1 ) )
                        {
                            = kind TT_FMT_FLOAT
                            = j + j 1
                            ~ & < j n ( fmt_is_digit ( nurl_str_get src j ) ) {
                                = j + j 1
                            }
                            : i ec ( nurl_str_get src j )
                            ? | == ec 101 == ec 69 {
                                = j + j 1
                                : i es ( nurl_str_get src j )
                                ? | == es 43 == es 45 {
                                    = j + j 1
                                } {}
                                ~ & < j n ( fmt_is_digit ( nurl_str_get src j ) ) {
                                    = j + j 1
                                }
                            } {}
                        } {}
                        ( __fmt_emit toks src i j kind nl_acc )
                        = nl_acc 0
                        = i j
                    } {

                        // 5) Identifier (folds in type keywords and T/F bool).
                        //    IDENT_PLAIN [ '::' IDENT_PLAIN ]*
                        ? ( fmt_is_ident_start c ) {
                            : ~ i j + i 1
                            ~ & < j n ( fmt_is_ident_cont ( nurl_str_get src j ) ) {
                                = j + j 1
                            }
                            ~ & & < + j 1 n
                            == ( nurl_str_get src j ) 58
                            == ( nurl_str_get src + j 1 ) 58
                            {
                                = j + j 2
                                ~ & < j n ( fmt_is_ident_cont ( nurl_str_get src j ) ) {
                                    = j + j 1
                                }
                            }
                            ( __fmt_emit toks src i j TT_FMT_IDENT nl_acc )
                            = nl_acc 0
                            = i j
                        } {

                            // 6) Multi-byte arrow `→` (E2 86 92)
                            ? ( __fmt_is_arrow src i ) {
                                ( __fmt_emit toks src i + i 3 TT_FMT_OP nl_acc )
                                = nl_acc 0
                                = i + i 3
                            } {

                            // 6b) Ellipsis `...` — grammar v1.9 variadic-FFI
                            //     marker. Must precede the single-byte `.`
                            //     fallback so three dots fuse into one OP
                            //     token rather than three. nurl_str_get
                            //     returns 0 for OOB indices, so the third-
                            //     byte check is bounds-safe at end-of-input.
                            ? & & == c 46 == c2 46 == ( nurl_str_get src + i 2 ) 46 {
                                ( __fmt_emit toks src i + i 3 TT_FMT_OP nl_acc )
                                = nl_acc 0
                                = i + i 3
                            } {

                                // 7) Two-char operators
                                ? & == c 61 == c2 61 {  // ==
                                    ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                    = nl_acc 0
                                    = i + i 2
                                } {
                                    ? & == c 33 == c2 61 {  // !=
                                        ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                        = nl_acc 0
                                        = i + i 2
                                    } {
                                        ? & == c 60 == c2 61 {  // <=
                                            ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                            = nl_acc 0
                                            = i + i 2
                                        } {
                                            ? & == c 62 == c2 61 {  // >=
                                                ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                = nl_acc 0
                                                = i + i 2
                                            } {
                                                ? & == c 60 == c2 60 {  // <<
                                                    ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                    = nl_acc 0
                                                    = i + i 2
                                                } {
                                                    ? & == c 62 == c2 62 {  // >>
                                                        ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                        = nl_acc 0
                                                        = i + i 2
                                                    } {
                                                        ? & == c 63 == c2 63 {  // ??
                                                            ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                            = nl_acc 0
                                                            = i + i 2
                                                        } {
                                                          ? & == c 94 == c2 94 {  // ^^
                                                            ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                            = nl_acc 0
                                                            = i + i 2
                                                          } {
                                                           ? & == c 124 == c2 124 {  // ||
                                                            ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                            = nl_acc 0
                                                            = i + i 2
                                                           } {
                                                            ? & == c 38 == c2 38 {  // &&
                                                             ( __fmt_emit toks src i + i 2 TT_FMT_OP nl_acc )
                                                             = nl_acc 0
                                                             = i + i 2
                                                            } {

                                                            // 8) Fallback: emit any single byte as an OP token. Whitelisted
                                                            //    grammar bytes go through this path; unknown bytes too,
                                                            //    so the round-trip test catches any mismatch.
                                                            ( __fmt_emit toks src i + i 1 TT_FMT_OP nl_acc )
                                                            = nl_acc 0
                                                            = i + i 1

                                                          } } } } } } } } } } } } } } } }
        } {}
    }

    : i nl_clamped ? > nl_acc 2 2 nl_acc
    ( vec_push [FmtTok] toks @ FmtTok { TT_FMT_EOF `` nl_clamped } )
    ^ toks
}

// Release every token's owned text plus the backing vec.
@ tokens_free ( Vec FmtTok ) toks → v {
    : i n ( vec_len [FmtTok] toks )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [FmtTok] toks i ) {
            T t → ( nurl_free . t text )
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [FmtTok] toks )
}
