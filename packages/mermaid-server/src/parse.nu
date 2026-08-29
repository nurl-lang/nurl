// mermaid-server/src/parse.nu — the mermaid flowchart parser.
//
// Accepts the `graph` / `flowchart` dialect: a direction header, node
// declarations with the thirteen mermaid shapes, and link chains with the
// solid / dotted / thick line styles, arrow / circle / cross heads,
// bidirectional links, `&` node groups, and both label spellings
// (`-->|text|` and `-- text -->`).
//
// Everything is byte-oriented and single-pass. The cursor and the error
// slot live behind `*MmdParser` — a heap pointer, because NURL structs are
// passed BY VALUE and every helper here has to advance the shared cursor.
//
// Statements the flowchart grammar has but this parser does not model
// (`classDef`, `class`, `style`, `linkStyle`, `click`, accessibility
// statements) are skipped with a warning that travels out on the graph, so
// a caller can surface "rendered, but I ignored line 7". `subgraph` is a
// hard error rather than a warning: dropping a subgraph silently would
// change the diagram's meaning, not just its styling.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `graph.nu`

// ── Parser state ─────────────────────────────────────────────────────

: MmdParser {
    s src
    i n
    i pos
    i stop  // end of the statement currently being parsed
    i line
    i line_start
    b failed
    String err
    i err_line
    i err_col
}

@ __mmd_parser_new s src → *MmdParser {
    : *MmdParser ps # *MmdParser ( nurl_alloc Z MmdParser )
    = . ps src src
    = . ps n ( nurl_str_len src )
    = . ps pos 0
    = . ps stop ( nurl_str_len src )
    = . ps line 1
    = . ps line_start 0
    = . ps failed F
    = . ps err ( string_new )
    = . ps err_line 0
    = . ps err_col 0
    ^ ps
}

@ __mmd_parser_free * MmdParser ps → v {
    ( string_free . ps err )
    ( nurl_free # s ps )
}

// Byte at `p`, or -1 past the end of the current statement window.
@ __mmd_at * MmdParser ps i p → i {
    ? >= p . ps stop { ^ - 0 1 } {}
    ? < p 0 { ^ - 0 1 } {}
    ^ ( nurl_str_at . ps src . ps n p )
}

// Byte at `p` ignoring the statement window (used by the statement
// splitter, which runs over the whole source).
@ __mmd_raw_at * MmdParser ps i p → i {
    ? >= p . ps n { ^ - 0 1 } {}
    ? < p 0 { ^ - 0 1 } {}
    ^ ( nurl_str_at . ps src . ps n p )
}

@ __mmd_fail * MmdParser ps s msg i at → v {
    ? . ps failed { ^ v } {}
    = . ps failed T
    ( string_clear . ps err )
    ( string_push_str . ps err msg )
    = . ps err_line . ps line
    = . ps err_col + 1 - at . ps line_start
}

@ __mmd_is_space i c → b {
    ? == c 32 { ^ T } {}
    ? == c 9 { ^ T } {}
    ? == c 13 { ^ T } {}
    ^ F
}

@ __mmd_is_alpha i c → b {
    | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ __mmd_is_digit i c → b { ^ & >= c 48 <= c 57 }

// Identifier bytes: ASCII alphanumerics, `_`, and every byte >= 0x80 so
// UTF-8 ids work. Everything else (including `-` and `.`, which start
// links) terminates the id.
@ __mmd_is_id i c → b {
    ? ( __mmd_is_alpha c ) { ^ T } {}
    ? ( __mmd_is_digit c ) { ^ T } {}
    ? == c 95 { ^ T } {}
    ? >= c 128 { ^ T } {}
    ^ F
}

// A byte that can be part of a link's line run: `-`, `=`, `.`.
@ __mmd_is_line i c → b {
    ? == c 45 { ^ T } {}
    ? == c 61 { ^ T } {}
    ? == c 46 { ^ T } {}
    ^ F
}

@ __mmd_skip_space * MmdParser ps → v {
    : ~ i p . ps pos
    ~ ( __mmd_is_space ( __mmd_at ps p ) ) { = p + p 1 }
    = . ps pos p
}

// ── Source slices ────────────────────────────────────────────────────

@ __mmd_slice * MmdParser ps i from i to → String {
    : ~ i a from
    : ~ i b to
    ? < a 0 { = a 0 } {}
    ? > b . ps n { = b . ps n } {}
    ? > a b { = a b } {}
    : String out ( string_with_cap + 1 - b a )
    : ~ i k a
    ~ < k b {
        ( string_push_char out ( nurl_str_at . ps src . ps n k ) )
        = k + k 1
    }
    ^ out
}

@ __mmd_slice_trim * MmdParser ps i from i to → String {
    : ~ i a from
    : ~ i b to
    ~ & < a b ( __mmd_is_space ( nurl_str_at . ps src . ps n a ) ) { = a + a 1 }
    ~ & < a b ( __mmd_is_space ( nurl_str_at . ps src . ps n - b 1 ) ) { = b - b 1 }
    ^ ( __mmd_slice ps a b )
}

// ── Label normalisation ──────────────────────────────────────────────
//
// Strips one layer of `"` quoting, turns `<br>` / `<br/>` / `<br />` into
// a newline (the renderer splits on it), and decodes the handful of HTML
// entities mermaid users actually type. CONSUMES `raw`.

@ __mmd_label_clean String raw → String {
    : String trimmed ( string_trim raw )
    ( string_free raw )
    : i n ( string_len trimmed )
    : ~ String body trimmed
    ? >= n 2 {
        ? & == ( string_get trimmed 0 ) 34 == ( string_get trimmed - n 1 ) 34 {
            : String inner ( string_substr trimmed 1 - n 2 )
            ( string_free trimmed )
            = body inner
        } {}
    } {}
    : String a ( string_replace body `<br/>` `\n` )
    ( string_free body )
    : String b ( string_replace a `<br />` `\n` )
    ( string_free a )
    : String c ( string_replace b `<br>` `\n` )
    ( string_free b )
    : String d ( string_replace c `&lt;` `<` )
    ( string_free c )
    : String e ( string_replace d `&gt;` `>` )
    ( string_free d )
    : String f ( string_replace e `&quot;` `"` )
    ( string_free e )
    : String g ( string_replace f `&amp;` `&` )
    ( string_free f )
    ^ g
}

// ── Node specs ───────────────────────────────────────────────────────
//
// `__mmd_shape_close` finds the byte range of a shape's label given the
// opener at `pos`, and reports the shape and the position just past the
// closing delimiter. `ok = F` means "unterminated".

: MmdShapeRes {
    b ok
    i shape
    i from
    i to
    i pos
}

// Index of `needle` (1 or 2 bytes) at or after `from`, within the
// statement window; -1 if absent. Quoted spans are skipped so a `]` inside
// `"..."` does not close the shape.
@ __mmd_find_close * MmdParser ps i from i c0 i c1 → i {
    : ~ i p from
    : ~ b inq F
    : ~ i hit - 0 1
    ~ & < 0 1 == hit - 0 1 {
        : i c ( __mmd_at ps p )
        ? == c - 0 1 { ^ - 0 1 } {}
        ? == c 34 { = inq ! inq } {}
        ? ! inq {
            ? == c c0 {
                ? == c1 - 0 1 { = hit p } {
                    ? == ( __mmd_at ps + p 1 ) c1 { = hit p } {}
                }
            } {}
        } {}
        = p + p 1
    }
    ^ hit
}

@ __mmd_shape_at * MmdParser ps i pos → MmdShapeRes {
    : i c0 ( __mmd_at ps pos )
    : i c1 ( __mmd_at ps + pos 1 )

    ? == c0 91 {  // `[`
        ? == c1 91 {  // `[[` subroutine
            : i e ( __mmd_find_close ps + pos 2 93 93 )
            ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
            ^ @ MmdShapeRes { T MMD_SHAPE_SUBROUTINE + pos 2 e + e 2 }
        } {}
        ? == c1 40 {  // `[(` cylinder
            : i e ( __mmd_find_close ps + pos 2 41 93 )
            ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
            ^ @ MmdShapeRes { T MMD_SHAPE_CYLINDER + pos 2 e + e 2 }
        } {}
        ? == c1 47 {  // `[/` parallelogram or trapezoid
            : i e1 ( __mmd_find_close ps + pos 2 47 93 )
            : i e2 ( __mmd_find_close ps + pos 2 92 93 )
            : b use1 & >= e1 0 | < e2 0 < e1 e2
            ? use1 { ^ @ MmdShapeRes { T MMD_SHAPE_PARALLELOGRAM + pos 2 e1 + e1 2 } } {}
            ? >= e2 0 { ^ @ MmdShapeRes { T MMD_SHAPE_TRAPEZOID + pos 2 e2 + e2 2 } } {}
            ^ @ MmdShapeRes { F 0 0 0 pos }
        } {}
        ? == c1 92 {  // `[\` parallelogram-alt or trapezoid-alt
            : i e1 ( __mmd_find_close ps + pos 2 92 93 )
            : i e2 ( __mmd_find_close ps + pos 2 47 93 )
            : b use1 & >= e1 0 | < e2 0 < e1 e2
            ? use1 { ^ @ MmdShapeRes { T MMD_SHAPE_PARALLELOGRAM_ALT + pos 2 e1 + e1 2 } } {}
            ? >= e2 0 { ^ @ MmdShapeRes { T MMD_SHAPE_TRAPEZOID_ALT + pos 2 e2 + e2 2 } } {}
            ^ @ MmdShapeRes { F 0 0 0 pos }
        } {}
        : i e ( __mmd_find_close ps + pos 1 93 - 0 1 )
        ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
        ^ @ MmdShapeRes { T MMD_SHAPE_RECT + pos 1 e + e 1 }
    } {}

    ? == c0 40 {  // `(`
        ? == c1 40 {  // `((` circle
            : i e ( __mmd_find_close ps + pos 2 41 41 )
            ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
            ^ @ MmdShapeRes { T MMD_SHAPE_CIRCLE + pos 2 e + e 2 }
        } {}
        ? == c1 91 {  // `([` stadium
            : i e ( __mmd_find_close ps + pos 2 93 41 )
            ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
            ^ @ MmdShapeRes { T MMD_SHAPE_STADIUM + pos 2 e + e 2 }
        } {}
        : i e ( __mmd_find_close ps + pos 1 41 - 0 1 )
        ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
        ^ @ MmdShapeRes { T MMD_SHAPE_ROUND + pos 1 e + e 1 }
    } {}

    ? == c0 123 {  // `{`
        ? == c1 123 {  // `{{` hexagon
            : i e ( __mmd_find_close ps + pos 2 125 125 )
            ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
            ^ @ MmdShapeRes { T MMD_SHAPE_HEXAGON + pos 2 e + e 2 }
        } {}
        : i e ( __mmd_find_close ps + pos 1 125 - 0 1 )
        ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
        ^ @ MmdShapeRes { T MMD_SHAPE_DIAMOND + pos 1 e + e 1 }
    } {}

    ? == c0 62 {  // `>` flag
        : i e ( __mmd_find_close ps + pos 1 93 - 0 1 )
        ? < e 0 { ^ @ MmdShapeRes { F 0 0 0 pos } } {}
        ^ @ MmdShapeRes { T MMD_SHAPE_FLAG + pos 1 e + e 1 }
    } {}

    ^ @ MmdShapeRes { F - 0 1 0 0 pos }  // shape = -1: no opener here
}

// Parse `id` + optional shape, interning the node. Returns its index, or
// -1 with the parser's error slot set.
@ __mmd_parse_node * MmdParser ps MmdGraph g → i {
    ( __mmd_skip_space ps )
    : i start . ps pos
    : ~ i p start
    ~ ( __mmd_is_id ( __mmd_at ps p ) ) { = p + p 1 }
    ? == p start {
        ( __mmd_fail ps `expected a node id` start )
        ^ - 0 1
    } {}
    : String id ( __mmd_slice ps start p )
    : i idx ( mmd_node_index g ( string_data id ) )
    ( string_free id )
    = . ps pos p

    : MmdShapeRes sh ( __mmd_shape_at ps p )
    ? & ! . sh ok == . sh shape - 0 1 { ^ idx } {}  // plain `A`, no shape
    ? ! . sh ok {
        ( __mmd_fail ps `unterminated node shape — no closing delimiter on this line` p )
        ^ - 0 1
    } {}
    : String label ( __mmd_label_clean ( __mmd_slice ps . sh from . sh to ) )
    ( mmd_node_declare g idx label . sh shape )
    = . ps pos . sh pos
    ^ idx
}

// `A & B & C` — a node group. Returns the interned indices; empty on error.
@ __mmd_parse_node_group * MmdParser ps MmdGraph g → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : ~ b going T
    ~ going {
        : i idx ( __mmd_parse_node ps g )
        ? < idx 0 { ^ out } {}
        ( vec_push [i] out idx )
        ( __mmd_skip_space ps )
        ? == ( __mmd_at ps . ps pos ) 38 {  // `&`
            = . ps pos + . ps pos 1
        } { = going F }
    }
    ^ out
}

// ── Links ────────────────────────────────────────────────────────────

: MmdLinkRes {
    b ok
    i line
    i head
    i tail
    i lab_from
    i lab_to
    i pos
}

@ __mmd_link_none → MmdLinkRes { ^ @ MmdLinkRes { F 0 0 0 0 0 0 } }

// Classify a run of line bytes [from,to): dotted wins over thick.
@ __mmd_line_style * MmdParser ps i from i to → i {
    : ~ b dot F
    : ~ b thick F
    : ~ i k from
    ~ < k to {
        : i c ( __mmd_at ps k )
        ? == c 46 { = dot T } {}
        ? == c 61 { = thick T } {}
        = k + k 1
    }
    ? dot { ^ MMD_LINE_DOTTED } {}
    ? thick { ^ MMD_LINE_THICK } {}
    ^ MMD_LINE_SOLID
}

@ __mmd_head_of i c → i {
    ? == c 62 { ^ MMD_ARROW_POINT } {}
    ? == c 111 { ^ MMD_ARROW_CIRCLE } {}
    ? == c 120 { ^ MMD_ARROW_CROSS } {}
    ^ MMD_ARROW_NONE
}

// Scan a link starting at `ps.pos`. `ok = F` means "no link here" and the
// cursor is untouched.
@ __mmd_scan_link * MmdParser ps → MmdLinkRes {
    ( __mmd_skip_space ps )
    : ~ i p . ps pos
    : ~ i tail MMD_ARROW_NONE

    : i c0 ( __mmd_at ps p )
    ? | == c0 60 | == c0 111 == c0 120 {
        : i c1 ( __mmd_at ps + p 1 )
        ? | == c1 45 == c1 61 {
            ? == c0 60 { = tail MMD_ARROW_POINT } {}
            ? == c0 111 { = tail MMD_ARROW_CIRCLE } {}
            ? == c0 120 { = tail MMD_ARROW_CROSS } {}
            = p + p 1
        } {}
    } {}

    : i run_from p
    ~ ( __mmd_is_line ( __mmd_at ps p ) ) { = p + p 1 }
    : i run_len - p run_from
    ? < run_len 2 { ^ ( __mmd_link_none ) } {}

    : i style ( __mmd_line_style ps run_from p )
    : ~ i head ( __mmd_head_of ( __mmd_at ps p ) )
    ? != head MMD_ARROW_NONE { = p + p 1 } {}

    : ~ i lab_from 0
    : ~ i lab_to 0

    // Inline-label form: an OPENING run is exactly `--`, `==` or `-.`
    // with no head. Anything longer (`---`, `-.-`, `===`) is a complete
    // unlabelled link, so `A --- B --- C` never reads `B` as a label.
    ? & == head MMD_ARROW_NONE == run_len 2 {
        : ~ i q p
        : ~ i found - 0 1
        ~ & == found - 0 1 < q . ps stop {
            : i c ( __mmd_at ps q )
            ? ( __mmd_is_line c ) {
                : i nx ( __mmd_at ps + q 1 )
                ? | ( __mmd_is_line nx ) == nx 62 { = found q } {}
            } {}
            = q + q 1
        }
        ? >= found 0 {
            = lab_from p
            = lab_to found
            = p found
            ~ ( __mmd_is_line ( __mmd_at ps p ) ) { = p + p 1 }
            = head ( __mmd_head_of ( __mmd_at ps p ) )
            ? != head MMD_ARROW_NONE { = p + p 1 } {}
        } {}
    } {}

    // Pipe-label form: `-->|text|`.
    ? == lab_to lab_from {
        : ~ i q p
        ~ ( __mmd_is_space ( __mmd_at ps q ) ) { = q + q 1 }
        ? == ( __mmd_at ps q ) 124 {
            : i e ( __mmd_find_close ps + q 1 124 - 0 1 )
            ? >= e 0 {
                = lab_from + q 1
                = lab_to e
                = p + e 1
            } {}
        } {}
    } {}

    ^ @ MmdLinkRes { T style head tail lab_from lab_to p }
}

// ── Statement dispatch ───────────────────────────────────────────────

// Leading `[A-Za-z]` word of the current statement, lowercased. Empty when
// the statement does not start with a letter.
@ __mmd_peek_word * MmdParser ps → String {
    : ~ i p . ps pos
    ~ ( __mmd_is_space ( __mmd_at ps p ) ) { = p + p 1 }
    : i start p
    ~ ( __mmd_is_alpha ( __mmd_at ps p ) ) { = p + p 1 }
    : String w ( __mmd_slice ps start p )
    : String lower ( string_to_lower w )
    ( string_free w )
    ^ lower
}

@ __mmd_word_is String w s lit → b {
    ^ != 0 ( nurl_str_eq ( string_data w ) lit )
}

// A statement that only styles or annotates: recorded as a warning and
// skipped. Returns T when `w` names one.
@ __mmd_is_ignorable String w → b {
    ? ( __mmd_word_is w `classdef` ) { ^ T } {}
    ? ( __mmd_word_is w `class` ) { ^ T } {}
    ? ( __mmd_word_is w `style` ) { ^ T } {}
    ? ( __mmd_word_is w `linkstyle` ) { ^ T } {}
    ? ( __mmd_word_is w `click` ) { ^ T } {}
    ? ( __mmd_word_is w `acctitle` ) { ^ T } {}
    ? ( __mmd_word_is w `accdescr` ) { ^ T } {}
    ^ F
}

@ __mmd_warn_ignored MmdGraph g String w i line → v {
    : String m ( string_with_cap 64 )
    ( string_push_str m `line ` )
    ( string_push_int m line )
    ( string_push_str m `: ignored unsupported statement '` )
    ( string_push_str m ( string_data w ) )
    ( string_push_str m `'` )
    ( vec_push [String] . g warnings m )
}

// Parse one chain statement: node group, then link + node group, repeating.
@ __mmd_parse_chain * MmdParser ps MmdGraph g → v {
    : ~ ( Vec i ) left ( __mmd_parse_node_group ps g )
    ? . ps failed { ( vec_free [i] left ) ^ v } {}

    : ~ b going T
    ~ going {
        ( __mmd_skip_space ps )
        ? >= . ps pos . ps stop { = going F } {
            : MmdLinkRes lk ( __mmd_scan_link ps )
            ? ! . lk ok {
                ( __mmd_fail ps `expected a link (--> --- -.-> ==> ...) or the end of the statement` . ps pos )
                = going F
            } {
                = . ps pos . lk pos
                : ( Vec i ) right ( __mmd_parse_node_group ps g )
                ? . ps failed {
                    ( vec_free [i] right )
                    = going F
                } {
                    : i nl ( vec_len [i] left )
                    : i nr ( vec_len [i] right )
                    : ~ i a 0
                    ~ < a nl {
                        : ~ i b 0
                        ~ < b nr {
                            : String lab ? > . lk lab_to . lk lab_from
                            ( __mmd_label_clean ( __mmd_slice_trim ps . lk lab_from . lk lab_to ) )
                            ( string_new )
                            ?? ( vec_get [i] left a ) {
                                T u → {
                                    ?? ( vec_get [i] right b ) {
                                        T w → ( mmd_add_edge g u w lab . lk line . lk head . lk tail )
                                        F _ → ( string_free lab )
                                    }
                                }
                                F _ → ( string_free lab )
                            }
                            = b + b 1
                        }
                        = a + a 1
                    }
                    ( vec_free [i] left )
                    = left right
                }
            }
        }
    }
    ( vec_free [i] left )
}

// ── Statement splitting ──────────────────────────────────────────────
//
// A statement runs to an unquoted, unbracketed `\n`, `;` or `%%`. The
// returned index is the exclusive end; `__mmd_advance_past` then moves the
// cursor over the terminator, keeping the line counter honest.

@ __mmd_stmt_end * MmdParser ps i from → i {
    : ~ i p from
    : ~ i depth 0
    : ~ b inq F
    ~ < p . ps n {
        : i c ( __mmd_raw_at ps p )
        ? == c 34 { = inq ! inq = p + p 1 } {
            ? inq { = p + p 1 } {
                ? | == c 91 | == c 40 == c 123 { = depth + depth 1 = p + p 1 } {
                    ? | == c 93 | == c 41 == c 125 {
                        ? > depth 0 { = depth - depth 1 } {}
                        = p + p 1
                    } {
                        ? == c 10 { ^ p } {}
                        ? & == depth 0 == c 59 { ^ p } {}
                        ? & == c 37 == ( __mmd_raw_at ps + p 1 ) 37 { ^ p } {}
                        = p + p 1
                    }
                }
            }
        }
    }
    ^ . ps n
}

// Skip blanks, newlines and `%%` comments; leaves the cursor on the first
// byte of the next statement (or at EOF).
@ __mmd_skip_blanks * MmdParser ps → v {
    : ~ b going T
    ~ going {
        : i c ( __mmd_raw_at ps . ps pos )
        ? == c 10 {
            = . ps pos + . ps pos 1
            = . ps line + . ps line 1
            = . ps line_start . ps pos
        } {
            ? | ( __mmd_is_space c ) == c 59 { = . ps pos + . ps pos 1 } {
                ? & == c 37 == ( __mmd_raw_at ps + . ps pos 1 ) 37 {
                    ~ & < . ps pos . ps n != ( __mmd_raw_at ps . ps pos ) 10 {
                        = . ps pos + . ps pos 1
                    }
                } { = going F }
            }
        }
    }
}

// ── Entry point ──────────────────────────────────────────────────────

: MmdParseResult {
    b ok
    MmdGraph graph
    String message
    i line
    i col
}

@ mmd_parse_result_free MmdParseResult r → v {
    ( mmd_graph_free . r graph )
    ( string_free . r message )
}

@ __mmd_bad_header String w i line → MmdParseResult {
    : String m ( string_with_cap 160 )
    ( string_push_str m `expected 'graph <dir>' or 'flowchart <dir>' as the first statement` )
    ? > ( string_len w ) 0 {
        ( string_push_str m `, found '` )
        ( string_push_str m ( string_data w ) )
        ( string_push_str m `' — only flowcharts are supported so far` )
    } {}
    ^ @ MmdParseResult { F ( mmd_graph_new ) m line 1 }
}

@ mmd_parse s src → MmdParseResult {
    : MmdGraph g ( mmd_graph_new )
    : *MmdParser ps ( __mmd_parser_new src )

    // Header.
    ( __mmd_skip_blanks ps )
    : i hstop ( __mmd_stmt_end ps . ps pos )
    = . ps stop hstop
    : String hw ( __mmd_peek_word ps )
    : b is_graph | ( __mmd_word_is hw `graph` ) ( __mmd_word_is hw `flowchart` )
    ? ! is_graph {
        : MmdParseResult bad ( __mmd_bad_header hw . ps line )
        ( string_free hw )
        ( mmd_graph_free g )
        ( __mmd_parser_free ps )
        ^ bad
    } {}
    = . ps pos + . ps pos ( string_len hw )
    ( string_free hw )
    ( __mmd_skip_space ps )
    : String dirw ( __mmd_slice_trim ps . ps pos hstop )
    ? > ( string_len dirw ) 0 {
        : i d ( mmd_dir_parse ( string_data dirw ) )
        ? >= d 0 { = . g dir d } {
            : String m ( string_with_cap 96 )
            ( string_push_str m `line ` )
            ( string_push_int m . ps line )
            ( string_push_str m `: unknown direction '` )
            ( string_push_str m ( string_data dirw ) )
            ( string_push_str m `', using TD` )
            ( vec_push [String] . g warnings m )
        }
    } {}
    ( string_free dirw )
    = . ps pos hstop

    // Body.
    : ~ b going T
    ~ going {
        ( __mmd_skip_blanks ps )
        ? >= . ps pos . ps n { = going F } {
            : i e ( __mmd_stmt_end ps . ps pos )
            = . ps stop e
            : i stmt_line . ps line
            : String w ( __mmd_peek_word ps )
            ? ( __mmd_word_is w `subgraph` ) {
                ( __mmd_fail ps `subgraph is not supported yet — flatten the diagram or drop the subgraph block` . ps pos )
                = going F
            } {
                ? ( __mmd_word_is w `end` ) {
                    ( __mmd_fail ps `stray 'end' — subgraph blocks are not supported yet` . ps pos )
                    = going F
                } {
                    ? ( __mmd_word_is w `direction` ) {
                        : String rest ( __mmd_slice_trim ps + . ps pos ( string_len w ) e )
                        : i d ( mmd_dir_parse ( string_data rest ) )
                        ? >= d 0 { = . g dir d } {}
                        ( string_free rest )
                    } {
                        ? ( __mmd_is_ignorable w ) {
                            ( __mmd_warn_ignored g w stmt_line )
                        } { ( __mmd_parse_chain ps g ) }
                    }
                }
            }
            ( string_free w )
            ? . ps failed { = going F } { = . ps pos e }
        }
    }

    = . ps stop . ps n
    ? . ps failed {
        : String msg ( string_clone . ps err )
        : i el . ps err_line
        : i ec . ps err_col
        ( __mmd_parser_free ps )
        ^ @ MmdParseResult { F g msg el ec }
    } {}
    ( __mmd_parser_free ps )
    ^ @ MmdParseResult { T g ( string_new ) 0 0 }
}
